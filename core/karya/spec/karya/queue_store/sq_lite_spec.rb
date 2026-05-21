# frozen_string_literal: true

require 'fileutils'
require 'sqlite3'
require 'tmpdir'

RSpec.describe Karya::QueueStore::SQLite do
  subject(:store) { described_class.new(url: database_url, namespace:) }

  let(:created_at) { Time.utc(2026, 5, 5, 12, 0, 0) }
  let(:internal_namespace) { described_class.send(:const_get, :Internal) }
  let(:namespace) { 'sqlite-unit' }
  let(:database_directory) { Dir.mktmpdir('karya-sqlite-unit-') }
  let(:database_url) { "sqlite3:///#{File.join(database_directory, 'karya.sqlite3').sub(%r{\A/+}, '')}" }

  after do
    FileUtils.rm_rf(database_directory)
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
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'url must use sqlite:// or sqlite3://')

    expect do
      described_class.new(url: 'sqlite3:///:memory:', namespace:)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'url must include a durable SQLite file path')

    expect do
      described_class.new(url: 'sqlite3://', namespace:)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'url must include a durable SQLite file path')

    expect do
      described_class.new(url: database_url, namespace: ' ')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'namespace must be a non-empty String')

    expect do
      described_class.new(url: database_url, max_batch_size: 0)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /max_batch_size must be a positive Integer/)

    expect do
      described_class.new(url: database_url, token_generator: -> { 'manual-token' })
    end.to raise_error(
      Karya::InvalidQueueStoreOperationError,
      'token_generator is managed internally by Karya::QueueStore::SQLite'
    )
  end

  it 'builds a connection path from a non-localhost SQLite host component' do
    path = described_class::ConnectionPath.build(
      url: 'sqlite3://shared-volume/tmp/karya.sqlite3',
      present_string_class: described_class::PresentString
    )

    expect(path).to eq('shared-volume/tmp/karya.sqlite3')
  end

  it 'normalizes URI parsing failures into SQLite url validation errors' do
    allow(URI).to receive(:parse).and_raise(URI::InvalidURIError.new('bad sqlite uri'))

    expect do
      described_class::ConnectionPath.build(url: 'sqlite3:///tmp/karya.sqlite3', present_string_class: described_class::PresentString)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'invalid SQLite url: bad sqlite uri')
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

    second_store = described_class.new(url: database_url, namespace:)
    uniqueness_decision = second_store.uniqueness_decision(
      job: submission_job(
        id: 'job-2',
        uniqueness_key: 'account-1',
        uniqueness_scope: :queued
      ),
      now: created_at + 2
    )
    reservation = second_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 3)

    third_store = described_class.new(url: database_url, namespace:)
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

    second_store = described_class.new(url: database_url, namespace:)
    pause_report = second_store.pause_workflow(batch_id: :approval_batch, now: created_at + 2)
    resume_report = second_store.resume_workflow(batch_id: :approval_batch, now: created_at + 3)
    approval_report = second_store.approve_workflow_checkpoints(batch_id: :approval_batch, step_ids: [:review], now: created_at + 4)

    snapshot = described_class.new(url: database_url, namespace:).workflow_snapshot(batch_id: :approval_batch, now: created_at + 5)
    history = described_class.new(url: database_url, namespace:).workflow_history(batch_id: :approval_batch, now: created_at + 5)

    expect(pause_report.action).to eq(:pause_workflow)
    expect(resume_report.action).to eq(:resume_workflow)
    expect(approval_report.action).to eq(:approve_workflow_checkpoints)
    expect(snapshot.step_states).to eq('review' => :queued)
    expect(history.entries.map(&:action)).to include('pause_requested', 'resumed', 'approval_approved')
  end

  it 'restores persisted state after a failed mutation transaction' do
    store.enqueue(job: submission_job(id: 'job-1'), now: created_at + 1)
    allow(store.connection).to receive(:execute).and_wrap_original do |original, sql, *bind_vars|
      raise 'forced sqlite write failure' if sql.include?('INSERT INTO karya_queue_store_states')

      original.call(sql, *bind_vars)
    end

    expect do
      store.enqueue(job: submission_job(id: 'job-2'), now: created_at + 2)
    end.to raise_error(StandardError, /forced sqlite write failure/)

    recovered_store = described_class.new(url: database_url, namespace:)
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
      def execute(_sql, _bind_vars = nil)
        raise 'rollback failed'
      end
    end.new
    owner = instance_double(described_class)
    allow(owner).to receive(:connection).and_raise(NoMethodError, 'fallback connection only')
    mutex = internal_namespace.const_get(:PersistenceMutex).new(connection: failing_connection, owner:)

    expect(mutex.send(:safe_rollback)).to be_nil
  end

  it 'uses a deferred transaction for read-only synchronization' do
    observed_sql = []
    connection = Class.new do
      def initialize(observed_sql)
        @observed_sql = observed_sql
      end

      def execute(sql, _bind_vars = nil)
        @observed_sql << sql
        []
      end
    end.new(observed_sql)
    owner = instance_double(described_class, namespace: namespace)
    allow(owner).to receive(:connection).and_return(connection)
    allow(owner).to receive(:restore_state_snapshot)
    mutex = internal_namespace.const_get(:PersistenceMutex).new(connection:, owner:)

    mutex.read_only_synchronize { :ok }

    expect(observed_sql.first).to eq('BEGIN TRANSACTION')
  end

  it 'returns nil when owner state restoration fails inside the persistence mutex' do
    owner = instance_double(described_class)
    allow(owner).to receive(:restore_authoritative_state_after_failure).and_raise(StandardError, 'restore failed')
    mutex = internal_namespace.const_get(:PersistenceMutex).new(connection: store.connection, owner:)

    expect(mutex.send(:restore_owner_state_after_failure)).to be_nil
  end

  it 'falls back to the bootstrap connection when the owner cannot provide one' do
    fallback_connection = instance_double(SQLite3::Database)
    owner = instance_double(described_class)
    allow(owner).to receive(:connection).and_raise(NoMethodError, 'owner unavailable')
    mutex = internal_namespace.const_get(:PersistenceMutex).new(connection: fallback_connection, owner:)

    expect(mutex.send(:connection)).to be(fallback_connection)
  end

  it 're-raises connection failures instead of falling back to the bootstrap connection' do
    fallback_connection = instance_double(SQLite3::Database)
    owner = instance_double(described_class)
    allow(owner).to receive(:connection).and_raise(StandardError, 'owner unavailable')
    mutex = internal_namespace.const_get(:PersistenceMutex).new(connection: fallback_connection, owner:)

    expect do
      mutex.send(:connection)
    end.to raise_error(StandardError, 'owner unavailable')
  end

  it 'returns a configured SQLite connection even when busy_timeout is unavailable' do
    fake_connection = Object.new
    fake_connection.define_singleton_method(:results_as_hash=) { |_value| true }
    allow(SQLite3::Database).to receive(:new).and_return(fake_connection)

    connection = described_class::ConnectionBuilder.build('/tmp/karya.sqlite3')

    expect(connection).to be(fake_connection)
  end

  it 'closes the SQLite connection when initialization fails after the connection opens' do
    fake_connection = instance_double(SQLite3::Database, close: nil)
    fake_mutex = instance_double(internal_namespace.const_get(:PersistenceMutex))
    allow(described_class::ConnectionBuilder).to receive(:build).and_return(fake_connection)
    allow(internal_namespace.const_get(:PersistenceMutex)).to receive(:new).and_return(fake_mutex)
    allow(fake_mutex).to receive(:ensure_schema).and_raise(StandardError, 'schema failed')

    expect do
      described_class.new(url: database_url, namespace:)
    end.to raise_error(StandardError, 'schema failed')

    expect(fake_connection).to have_received(:close)
  end

  it 'reopens the SQLite connection after a fork before using the store again' do
    original_connection = instance_double(SQLite3::Database, close: nil)
    replacement_connection = instance_double(SQLite3::Database)
    allow(replacement_connection).to receive(:results_as_hash=)
    allow(replacement_connection).to receive(:busy_timeout=)
    store.instance_variable_set(:@connection, original_connection)
    store.instance_variable_set(:@connection_pid, Process.pid - 1)
    allow(described_class::ConnectionBuilder).to receive(:build).with(store.send(:connection_path)).and_return(replacement_connection)

    expect(store.connection).to be(replacement_connection)
    expect(original_connection).to have_received(:close)
  end

  it 'clears the inherited connection if reopening after fork fails' do
    original_connection = instance_double(SQLite3::Database, close: nil)
    store.instance_variable_set(:@connection, original_connection)
    store.instance_variable_set(:@connection_pid, Process.pid - 1)
    allow(described_class::ConnectionBuilder).to receive(:build).with(store.send(:connection_path)).and_raise(StandardError, 'reconnect failed')

    expect do
      store.connection
    end.to raise_error(StandardError, 'reconnect failed')

    expect(store.instance_variable_get(:@connection)).to be_nil
    expect(original_connection).to have_received(:close)
  end

  it 'reopens a forked SQLite store even when no inherited connection is present' do
    replacement_connection = instance_double(SQLite3::Database)
    allow(replacement_connection).to receive(:results_as_hash=)
    allow(replacement_connection).to receive(:busy_timeout=)
    store.instance_variable_set(:@connection, nil)
    store.instance_variable_set(:@connection_pid, Process.pid - 1)
    allow(described_class::ConnectionBuilder).to receive(:build).with(store.send(:connection_path)).and_return(replacement_connection)

    expect(store.connection).to be(replacement_connection)
  end

  it 'rejects malformed SQLite state payloads' do
    expect do
      internal_namespace.const_get(:StateCodec).load('not-base64')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid SQLite state snapshot/)
  end

  it 'rejects truncated SQLite state payloads' do
    truncated_payload = [Marshal.dump({ state: store.send(:state), reservation_token_sequence: 1 })[0...2]].pack('m0')

    expect do
      internal_namespace.const_get(:StateCodec).load(truncated_payload)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid SQLite state snapshot/)
  end

  it 'rejects invalid decoded SQLite state payloads' do
    payload = [Marshal.dump({ state: Object.new, reservation_token_sequence: 1 })].pack('m0')

    expect do
      internal_namespace.const_get(:StateCodec).load(payload)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid SQLite state snapshot/)
  end

  it 'rejects decoded SQLite state payloads with missing keys' do
    payload = [Marshal.dump({ reservation_token_sequence: 1 })].pack('m0')

    expect do
      internal_namespace.const_get(:StateCodec).load(payload)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid SQLite state snapshot/)
  end
end
