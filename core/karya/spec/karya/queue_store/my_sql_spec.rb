# frozen_string_literal: true

RSpec.describe Karya::QueueStore::MySQL do
  subject(:store) { described_class.new(url: mysql_url, namespace:) }

  let(:mysql_url) { 'mysql2://example.test/karya' }
  let(:created_at) { Time.utc(2026, 5, 5, 12, 0, 0) }
  let(:internal_namespace) { described_class.send(:const_get, :Internal) }
  let(:namespace) { 'mysql-unit' }
  let(:fake_connection_class) do
    Class.new do
      def initialize
        @rows = {}
        @fail_next_upsert = false
      end

      def query(sql, **_options)
        namespace = sql[/WHERE namespace = '([^']+)'/, 1]

        if sql.include?('SELECT payload')
          payload = @rows[namespace]
          return payload ? [{ 'payload' => payload }] : []
        end

        if sql.include?('INSERT INTO karya_queue_store_states')
          raise 'forced mysql write failure' if consume_fail_next_upsert

          values = sql.match(/VALUES \('([^']+)', '([^']+)', CURRENT_TIMESTAMP\(6\)\)/)
          @rows[values[1]] = values[2] if values
        end

        []
      end

      def escape(value)
        value.gsub("'", "\\\\'")
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
    stub_const('Mysql2', Module.new) unless defined?(Mysql2)
    stub_const('Mysql2::Client', Class.new)
    allow(dependency_loader).to receive(:require_mysql2!).and_return(true)
    allow(Mysql2::Client).to receive(:new).and_return(connection)
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
      described_class.new(url: 'postgres://example.test/karya', namespace:)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'url must use mysql:// or mysql2://')

    expect do
      described_class.new(url: 'mysql2://[invalid', namespace:)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid MySQL url:/)

    expect do
      described_class.new(url: 'mysql2:///karya?socket=%zz', namespace:)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid MySQL url:/)

    expect do
      described_class.new(url: 'mysql2://example.test', namespace:)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'url must include a database name')

    expect do
      described_class.new(url: mysql_url, namespace: ' ')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'namespace must be a non-empty String')

    expect do
      described_class.new(url: mysql_url, namespace: 'n' * 256)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'namespace must be at most 255 bytes')

    expect do
      described_class.new(url: mysql_url, max_batch_size: 0)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /max_batch_size must be a positive Integer/)
    expect(connection).to be_closed

    expect do
      described_class.new(url: mysql_url, token_generator: -> { 'manual-token' })
    end.to raise_error(
      Karya::InvalidQueueStoreOperationError,
      'token_generator is managed internally by Karya::QueueStore::MySQL'
    )
  end

  it 'supports socket-based MySQL URLs' do
    socket_url = 'mysql2:///karya?socket=%2Ftmp%2Fmysql.sock&encoding=utf8mb4'

    described_class.new(url: socket_url, namespace:)

    expect(Mysql2::Client).to have_received(:new).with(
      hash_including(
        socket: '/tmp/mysql.sock',
        database: 'karya',
        encoding: 'utf8mb4'
      )
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

    second_store = described_class.new(url: mysql_url, namespace:)
    uniqueness_decision = second_store.uniqueness_decision(
      job: submission_job(
        id: 'job-2',
        uniqueness_key: 'account-1',
        uniqueness_scope: :queued
      ),
      now: created_at + 2
    )
    reservation = second_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 3)

    third_store = described_class.new(url: mysql_url, namespace:)
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

    second_store = described_class.new(url: mysql_url, namespace:)
    pause_report = second_store.pause_workflow(batch_id: :approval_batch, now: created_at + 2)
    resume_report = second_store.resume_workflow(batch_id: :approval_batch, now: created_at + 3)
    approval_report = second_store.approve_workflow_checkpoints(batch_id: :approval_batch, step_ids: [:review], now: created_at + 4)

    snapshot = described_class.new(url: mysql_url, namespace:).workflow_snapshot(batch_id: :approval_batch, now: created_at + 5)
    history = described_class.new(url: mysql_url, namespace:).workflow_history(batch_id: :approval_batch, now: created_at + 5)

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
    end.to raise_error(StandardError, /forced mysql write failure/)

    recovered_store = described_class.new(url: mysql_url, namespace:)
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
    failing_connection = Class.new do
      def query(_sql, **_options)
        raise 'rollback failed'
      end
    end.new
    mutex = internal_namespace.const_get(:PersistenceMutex).new(connection: failing_connection, owner: store)

    expect(mutex.send(:safe_rollback)).to be_nil
  end

  it 'returns nil when owner state restoration fails inside the persistence mutex' do
    owner = instance_double(described_class)
    allow(owner).to receive(:restore_authoritative_state_after_failure).and_raise(StandardError, 'restore failed')
    mutex = internal_namespace.const_get(:PersistenceMutex).new(connection:, owner:)

    expect(mutex.send(:restore_owner_state_after_failure)).to be_nil
  end

  it 'creates a placeholder row before acquiring a FOR UPDATE lock on first write' do
    recorded_sql = []
    recording_connection = Class.new do
      def initialize(recorded_sql)
        @recorded_sql = recorded_sql
      end

      def query(sql, **_options)
        @recorded_sql << sql
        []
      end

      def escape(value)
        value.gsub("'", "\\\\'")
      end
    end.new(recorded_sql)
    mutex = internal_namespace.const_get(:PersistenceMutex).new(connection: recording_connection, owner: store)

    mutex.send(:lock_current_row)

    expect(recorded_sql[0]).to include('INSERT IGNORE INTO karya_queue_store_states')
    expect(recorded_sql[1]).to include('SELECT payload')
    expect(recorded_sql[1]).to include('FOR UPDATE')
  end

  it 'rejects malformed MySQL state payloads' do
    expect do
      internal_namespace.const_get(:StateCodec).load('not-base64')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid MySQL state snapshot/)
  end

  it 'rejects invalid decoded MySQL state payloads' do
    payload = [Marshal.dump({ state: Object.new, reservation_token_sequence: 1 })].pack('m0')

    expect do
      internal_namespace.const_get(:StateCodec).load(payload)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid MySQL state snapshot/)
  end

  it 'rejects decoded MySQL state payloads with missing keys' do
    payload = [Marshal.dump({ reservation_token_sequence: 1 })].pack('m0')

    expect do
      internal_namespace.const_get(:StateCodec).load(payload)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid MySQL state snapshot/)
  end
end
