# frozen_string_literal: true

RSpec.describe Karya::QueueStore::Postgres do
  subject(:store) { described_class.new(url: postgres_url, namespace:) }

  let(:postgres_url) { 'postgres://example.test/karya' }
  let(:created_at) { Time.utc(2026, 5, 5, 12, 0, 0) }
  let(:internal_namespace) { described_class.send(:const_get, :Internal) }
  let(:namespace) { 'postgres-unit' }
  let(:fake_connection_class) do
    result_class = Struct.new(:rows) do
      def ntuples = rows.length
      def [](index) = rows.fetch(index)
    end

    Class.new do
      define_singleton_method(:result_class) { result_class }

      def initialize
        @rows = {}
        @fail_next_upsert = false
      end

      def exec(_sql)
        self.class.result_class.new([])
      end

      def exec_params(sql, params)
        namespace = params.fetch(0)
        if sql.include?('SELECT payload')
          payload = @rows[namespace]
          rows = payload ? [{ 'payload' => payload }] : []
          return self.class.result_class.new(rows)
        end

        if sql.include?('INSERT INTO karya_queue_store_states')
          raise 'forced postgres write failure' if consume_fail_next_upsert

          @rows[namespace] = params.fetch(1)
        end

        self.class.result_class.new([])
      end

      def fail_next_upsert!
        @fail_next_upsert = true
      end

      def close
        @closed = true
      end

      def closed?
        @closed
      end

      private

      def consume_fail_next_upsert
        should_fail = @fail_next_upsert
        @fail_next_upsert = false
        should_fail
      end
    end
  end
  let(:connection) { fake_connection_class.new }
  let(:dependency_loader) { internal_namespace.const_get(:DependencyLoader) }

  before do
    stub_const('PG', Module.new) unless defined?(PG)
    allow(dependency_loader).to receive(:require_pg!).and_return(true)
    allow(PG).to receive(:connect).with(postgres_url).and_return(connection)
  end

  def submission_job(
    id:,
    queue: 'billing',
    handler: 'billing_sync',
    retry_policy: nil,
    uniqueness_key: nil,
    uniqueness_scope: nil
  )
    Karya::Job.new(
      id:,
      queue:,
      handler:,
      state: :submission,
      created_at:,
      retry_policy:,
      uniqueness_key:,
      uniqueness_scope:
    )
  end

  def workflow_job(step_id, handler: step_id)
    Karya::Job.new(
      id: "job-#{step_id}",
      queue: :billing,
      handler:,
      state: :submission,
      created_at:
    )
  end

  it 'validates constructor inputs' do
    expect do
      described_class.new(url: '', namespace:)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'url must be a non-empty String')

    expect do
      described_class.new(url: Object.new, namespace:)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'url must be a non-empty String')

    expect do
      described_class.new(url: postgres_url, namespace: ' ')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'namespace must be a non-empty String')

    expect do
      described_class.new(url: postgres_url, max_batch_size: 0)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /max_batch_size must be a positive Integer/)
    expect(connection).to be_closed

    expect do
      described_class.new(url: postgres_url, token_generator: -> { 'manual-token' })
    end.to raise_error(
      Karya::InvalidQueueStoreOperationError,
      'token_generator is managed internally by Karya::QueueStore::Postgres'
    )
  end

  it 'does not inherit from the in-memory concrete store' do
    expect(described_class.superclass).not_to eq(Karya::QueueStore::InMemory)
  end

  it 'persists queued, reserved, and succeeded job state across instances' do
    store.enqueue(
      job: submission_job(
        id: 'job-1',
        uniqueness_key: 'account-1',
        uniqueness_scope: :queued
      ),
      now: created_at + 1
    )

    second_store = described_class.new(url: postgres_url, namespace:)
    uniqueness_decision = second_store.uniqueness_decision(
      job: submission_job(
        id: 'job-2',
        uniqueness_key: 'account-1',
        uniqueness_scope: :queued
      ),
      now: created_at + 2
    )
    reservation = second_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 3)

    third_store = described_class.new(url: postgres_url, namespace:)
    running = third_store.start_execution(reservation_token: reservation.token, now: created_at + 4)
    succeeded = third_store.complete_execution(reservation_token: reservation.token, now: created_at + 5)

    expect(uniqueness_decision.fetch(:action)).to eq(:reject)
    expect(running.state).to eq(:running)
    expect(succeeded.state).to eq(:succeeded)
  end

  it 'persists workflow control state across instances' do
    definition = Karya::Workflow.define(:approval_flow) do
      step :review, handler: :review, wait_for_approval: :manager_approved
    end

    store.enqueue_workflow(
      definition:,
      jobs_by_step_id: { review: workflow_job(:review, handler: :review) },
      batch_id: :approval_batch,
      now: created_at + 1
    )

    second_store = described_class.new(url: postgres_url, namespace:)
    pause_report = second_store.pause_workflow(batch_id: :approval_batch, now: created_at + 2)
    resume_report = second_store.resume_workflow(batch_id: :approval_batch, now: created_at + 3)
    approval_report = second_store.approve_workflow_checkpoints(batch_id: :approval_batch, step_ids: [:review], now: created_at + 4)

    snapshot = described_class.new(url: postgres_url, namespace:).workflow_snapshot(batch_id: :approval_batch, now: created_at + 5)
    history = described_class.new(url: postgres_url, namespace:).workflow_history(batch_id: :approval_batch, now: created_at + 5)

    expect(pause_report.action).to eq(:pause_workflow)
    expect(resume_report.action).to eq(:resume_workflow)
    expect(approval_report.action).to eq(:approve_workflow_checkpoints)
    expect(snapshot.step_states).to eq('review' => :queued)
    expect(history.entries.map(&:action)).to include('pause_requested', 'resumed', 'approval_approved')
  end

  it 'restores persisted state after a failed mutation transaction' do
    store.enqueue(job: submission_job(id: 'job-1'), now: created_at + 1)
    connection.fail_next_upsert!

    expect do
      store.enqueue(job: submission_job(id: 'job-2'), now: created_at + 2)
    end.to raise_error(StandardError, /forced postgres write failure/)

    recovered_store = described_class.new(url: postgres_url, namespace:)
    first = recovered_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 3)
    expect(first.job_id).to eq('job-1')
    expect(
      recovered_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 4)
    ).to be_nil
  end

  it 'returns nil when restoring authoritative state also fails' do
    failing_store = described_class.allocate
    allow(failing_store).to receive(:load_persisted_state).and_raise(StandardError, 'reload failed')

    expect(failing_store.restore_authoritative_state_after_failure).to be_nil
  end

  it 'returns nil when persistence mutex rollback also fails' do
    connection = Class.new do
      def exec(_sql)
        raise 'rollback failed'
      end
    end.new
    mutex = internal_namespace.const_get(:PersistenceMutex).new(connection:, owner: store)

    expect(mutex.send(:safe_rollback)).to be_nil
  end

  it 'returns nil when owner state restoration fails inside the persistence mutex' do
    owner = instance_double(described_class)
    allow(owner).to receive(:restore_authoritative_state_after_failure).and_raise(StandardError, 'restore failed')
    mutex = internal_namespace.const_get(:PersistenceMutex).new(connection:, owner:)

    expect(mutex.send(:restore_owner_state_after_failure)).to be_nil
  end

  it 'rejects malformed Postgres state payloads' do
    expect do
      internal_namespace.const_get(:StateCodec).load('not-base64')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid Postgres state snapshot/)
  end

  it 'rejects invalid decoded Postgres state payloads' do
    payload = [Marshal.dump({ state: Object.new, reservation_token_sequence: 1 })].pack('m0')

    expect do
      internal_namespace.const_get(:StateCodec).load(payload)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid Postgres state snapshot/)
  end

  it 'rejects decoded Postgres state payloads with missing keys' do
    payload = [Marshal.dump({ reservation_token_sequence: 1 })].pack('m0')

    expect do
      internal_namespace.const_get(:StateCodec).load(payload)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid Postgres state snapshot/)
  end
end
