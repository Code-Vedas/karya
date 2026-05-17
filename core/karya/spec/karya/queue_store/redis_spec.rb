# frozen_string_literal: true

RSpec.describe Karya::QueueStore::Redis do
  subject(:store) { described_class.new(url: redis_url, namespace:) }

  let(:redis_url) { 'redis://example.test:6379/0' }
  let(:created_at) { Time.utc(2026, 5, 5, 12, 0, 0) }
  let(:namespace) { 'redis-unit' }
  let(:persistence_mutex_class) { described_class.const_get(:Internal, false).const_get(:PersistenceMutex, false) }
  let(:fake_redis_client_class) do
    Class.new do
      attr_reader :data

      def initialize(eval_error: nil)
        @data = {}
        @eval_error = eval_error
      end

      def get(key)
        data[key]
      end

      def set(key, value, **options)
        if options.fetch(:nx, false)
          return nil if data.key?(key)

          data[key] = value
          return 'OK'
        end

        data[key] = value
        'OK'
      end

      def del(key)
        data.delete(key) ? 1 : 0
      end

      def incr(key)
        current_value = data[key]
        next_value = current_value ? Integer(current_value, 10) + 1 : 1
        data[key] = next_value.to_s
        next_value
      end

      def expire(key, _seconds)
        data.key?(key) ? 1 : 0
      end

      def eval(script, keys:, argv:)
        raise eval_error if eval_error

        key = keys.fetch(0)
        token = argv.fetch(0)
        return 0 unless get(key) == token

        if release_script?(script)
          del(key)
        elsif extend_script?(script)
          expire(key, argv.fetch(1))
        elsif increment_version_script?(script)
          persist_versioned_script(keys:, argv:)
        elsif compact_snapshot_script?(script)
          compact_snapshot(keys:, argv:)
        else
          raise "unsupported script: #{script}"
        end
      end

      private

      attr_reader :eval_error

      def release_script?(script)
        script.include?('return redis.call("del", KEYS[1])')
      end

      def extend_script?(script)
        script.include?('return redis.call("expire", KEYS[1], ARGV[2])')
      end

      def increment_version_script?(script)
        script.include?('local version = redis.call("incr", KEYS[2])')
      end

      def compact_snapshot_script?(script)
        script.include?('redis.call("set", KEYS[2], ARGV[2])')
      end

      def persist_versioned_script(keys:, argv:)
        version = incr(keys.fetch(1))
        return persist_snapshot_version(keys:, argv:, version:) if keys.length == 3

        data["#{argv.fetch(1)}#{version}"] = argv.fetch(2)
        expire(keys.fetch(0), argv.fetch(3))
        version
      end

      def persist_snapshot_version(keys:, argv:, version:)
        data[keys.fetch(2)] = argv.fetch(1)
        expire(keys.fetch(0), argv.fetch(2))
        version
      end

      def compact_snapshot(keys:, argv:)
        data[keys.fetch(1)] = argv.fetch(1)
        expire(keys.fetch(0), argv.fetch(2))
        1
      end
    end
  end
  let(:redis_client) { fake_redis_client_class.new }

  before do
    allow(Redis).to receive(:new).with(url: redis_url).and_return(redis_client)
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
      described_class.new(url: redis_url, namespace: ' ')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'namespace must be a non-empty String')

    expect do
      described_class.new(url: redis_url, max_batch_size: 0)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /max_batch_size must be a positive Integer/)

    expect do
      described_class.new(url: redis_url, policy_set: Object.new)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /policy_set must be a Karya::Backpressure::PolicySet/)

    expect do
      described_class.new(url: redis_url, fairness_policy: Object.new)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /fairness_policy must be a Karya::Fairness::Policy/)

    expect do
      described_class.new(url: redis_url, circuit_breaker_policy_set: Object.new)
    end.to raise_error(
      Karya::InvalidQueueStoreOperationError,
      /circuit_breaker_policy_set must be a Karya::CircuitBreaker::PolicySet/
    )

    expect do
      described_class.new(url: redis_url, token_generator: -> { 'manual-token' })
    end.to raise_error(
      Karya::InvalidQueueStoreOperationError,
      'token_generator is managed internally by Karya::QueueStore::Redis'
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

    second_store = described_class.new(url: redis_url, namespace:)
    uniqueness_decision = second_store.uniqueness_decision(
      job: submission_job(
        id: 'job-2',
        uniqueness_key: 'account-1',
        uniqueness_scope: :queued
      ),
      now: created_at + 2
    )
    reservation = second_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 3)

    third_store = described_class.new(url: redis_url, namespace:)
    running = third_store.start_execution(reservation_token: reservation.token, now: created_at + 4)
    succeeded = third_store.complete_execution(reservation_token: reservation.token, now: created_at + 5)

    expect(uniqueness_decision.fetch(:action)).to eq(:reject)
    expect(running.state).to eq(:running)
    expect(succeeded.state).to eq(:succeeded)
    expect(redis_client.data.fetch('redis-unit:queue_store:version')).to eq('4')
    expect(redis_client.data).to have_key('redis-unit:queue_store:event:4')
  end

  it 'replays pending journal entries incrementally for a stale Redis store instance' do
    store.enqueue(job: submission_job(id: 'job-1'), now: created_at + 1)

    described_class.new(url: redis_url, namespace:).enqueue(job: submission_job(id: 'job-2'), now: created_at + 2)

    first_reservation = store.reserve(queue: 'billing', worker_id: 'worker-incremental', lease_duration: 60, now: created_at + 3)
    second_reservation = store.reserve(queue: 'billing', worker_id: 'worker-incremental', lease_duration: 60, now: created_at + 4)

    expect(first_reservation.job_id).to eq('job-1')
    expect(second_reservation.job_id).to eq('job-2')
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

    second_store = described_class.new(url: redis_url, namespace:)
    pause_report = second_store.pause_workflow(batch_id: :approval_batch, now: created_at + 2)
    resume_report = second_store.resume_workflow(batch_id: :approval_batch, now: created_at + 3)
    approval_report = second_store.approve_workflow_checkpoints(batch_id: :approval_batch, step_ids: [:review], now: created_at + 4)

    snapshot = described_class.new(url: redis_url, namespace:).workflow_snapshot(batch_id: :approval_batch, now: created_at + 5)
    history = described_class.new(url: redis_url, namespace:).workflow_history(batch_id: :approval_batch, now: created_at + 5)

    expect(pause_report.action).to eq(:pause_workflow)
    expect(resume_report.action).to eq(:resume_workflow)
    expect(approval_report.action).to eq(:approve_workflow_checkpoints)
    expect(snapshot.step_states).to eq('review' => :queued)
    expect(history.entries.map(&:action)).to include('pause_requested', 'resumed', 'approval_approved')
  end

  it 'persists recovery and dead-letter flows across instances' do
    retry_policy = Karya::RetryPolicy.new(max_attempts: 2, base_delay: 5, multiplier: 1)
    store.enqueue(job: submission_job(id: 'job-retry', retry_policy:), now: created_at + 1)
    reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 2)
    store.start_execution(reservation_token: reservation.token, now: created_at + 3)

    failed_job = store.fail_execution(
      reservation_token: reservation.token,
      now: created_at + 4,
      failure_classification: :error,
      retry_policy:
    )
    retried = described_class.new(url: redis_url, namespace:).retry_jobs(job_ids: ['job-retry'], now: created_at + 10)
    dead_lettered = described_class.new(url: redis_url, namespace:).dead_letter_jobs(job_ids: ['job-retry'], now: created_at + 11, reason: 'manual')
    replayed = described_class.new(url: redis_url, namespace:).replay_dead_letter_jobs(job_ids: ['job-retry'], now: created_at + 12)

    expect(failed_job.state).to eq(:retry_pending)
    expect(retried.changed_jobs.fetch(0).state).to eq(:queued)
    expect(dead_lettered.changed_jobs.fetch(0).state).to eq(:dead_letter)
    expect(replayed.changed_jobs.fetch(0).state).to eq(:queued)
  end

  it 'persists release and completion journal events across instances' do
    store.enqueue(job: submission_job(id: 'job-release'), now: created_at + 1)
    initial_reservation = store.reserve(queue: 'billing', worker_id: 'worker-release', lease_duration: 60, now: created_at + 2)

    released_job = store.release(reservation_token: initial_reservation.token, now: created_at + 3)
    restored_store = described_class.new(url: redis_url, namespace:)
    replayed_reservation = restored_store.reserve(queue: 'billing', worker_id: 'worker-release', lease_duration: 60, now: created_at + 4)
    restored_store.start_execution(reservation_token: replayed_reservation.token, now: created_at + 5)
    restored_store.complete_execution(reservation_token: replayed_reservation.token, now: created_at + 6)

    terminal_store = described_class.new(url: redis_url, namespace:)

    expect(released_job.state).to eq(:queued)
    expect(replayed_reservation.job_id).to eq('job-release')
    expect(terminal_store.reserve(queue: 'billing', worker_id: 'worker-release', lease_duration: 60, now: created_at + 7)).to be_nil
  end

  it 'does not delete the distributed lock when release script execution fails' do
    fallback_client = fake_redis_client_class.new
    allow(Redis).to receive(:new).with(url: redis_url).and_return(fallback_client)
    allow(fallback_client).to receive(:eval).and_wrap_original do |original, script, keys:, argv:|
      raise 'boom' if script == persistence_mutex_class::RELEASE_SCRIPT

      original.call(script, keys:, argv:)
    end
    fallback_store = described_class.new(url: redis_url, namespace: 'fallback')

    expect do
      fallback_store.enqueue(job: submission_job(id: 'job-fallback'), now: created_at + 1)
    end.not_to raise_error

    expect(fallback_client.data).to have_key('fallback:queue_store:lock')
  end

  it 'rejects Symbol job arguments when Redis persistence is required' do
    expect do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-symbol-arg',
          queue: 'billing',
          handler: 'billing_sync',
          arguments: { 'kind' => :manual },
          state: :submission,
          created_at:
        ),
        now: created_at + 1
      )
    end.to raise_error(
      Karya::InvalidQueueStoreOperationError,
      'Redis queue-store snapshots do not support Symbol job arguments'
    )
  end

  it 'replays durable state from journal entries when the Redis snapshot key is missing' do
    store.enqueue(job: submission_job(id: 'job-fresh'), now: created_at + 1)
    redis_client.data.delete("#{namespace}:queue_store:state")

    restored_store = described_class.new(url: redis_url, namespace:)
    reservation = restored_store.reserve(queue: 'billing', worker_id: 'worker-reset', lease_duration: 60, now: created_at + 2)
    restored_job = restored_store.start_execution(reservation_token: reservation.token, now: created_at + 3)

    expect(restored_job.id).to eq('job-fresh')
    expect(restored_store.reserve(queue: 'billing', worker_id: 'worker-reset', lease_duration: 60, now: created_at + 4)).to be_nil
  end

  it 'persists jobs with concurrency and rate-limit scopes across Redis reloads' do
    store.enqueue(
      job: Karya::Job.new(
        id: 'job-scoped',
        queue: 'billing',
        handler: 'billing_sync',
        arguments: { 'invoice_id' => 'inv-42' },
        concurrency_scope: { kind: :tenant, value: 'tenant-42' },
        rate_limit_scope: { kind: :workflow, value: 'nightly-billing' },
        state: :submission,
        created_at:
      ),
      now: created_at + 1
    )

    restored_store = described_class.new(url: redis_url, namespace:)
    reservation = restored_store.reserve(queue: 'billing', worker_id: 'worker-scoped', lease_duration: 60, now: created_at + 2)
    restored_job = restored_store.start_execution(reservation_token: reservation.token, now: created_at + 3)

    expect(restored_job.concurrency_scope).to eq(Karya::Backpressure::Scope.new(kind: :tenant, value: 'tenant-42'))
    expect(restored_job.rate_limit_scope).to eq(Karya::Backpressure::Scope.new(kind: :workflow, value: 'nightly-billing'))
  end

  it 'rejects unsupported Redis journal event names' do
    expect do
      store.send(:apply_persisted_event, { 'name' => 'mystery', 'arguments' => {} })
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported Redis queue-store journal event/)
  end

  it 'returns false for incremental replay when the local Redis store is already current' do
    store.send(:journal_support).instance_variable_set(:@loaded_version, 2)

    expect(store.send(:can_replay_incrementally?, 2)).to be(false)
  end

  it 'raises when a journal event needed for replay is missing' do
    expect do
      store.send(:apply_persisted_events, 1..1)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /missing Redis queue-store journal event/)
  end

  it 'replays journal events without swapping the token generator when no reservation token is present' do
    original_token_generator = store.instance_variable_get(:@token_generator)

    store.send(:with_journal_replay) { nil }

    expect(store.instance_variable_get(:@token_generator)).to be(original_token_generator)
  end

  it 'rejects non-finite Float job arguments when Redis persistence is required' do
    expect do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-nan-arg',
          queue: 'billing',
          handler: 'billing_sync',
          arguments: { 'value' => Float::INFINITY },
          state: :submission,
          created_at:
        ),
        now: created_at + 1
      )
    end.to raise_error(
      Karya::InvalidQueueStoreOperationError,
      'Redis queue-store snapshots do not support non-finite Float job arguments'
    )
  end

  it 'reloads local state after a Redis event payload validation failure' do
    expect do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-invalid',
          queue: 'billing',
          handler: 'billing_sync',
          arguments: { 'kind' => :symbol_value },
          state: :submission,
          created_at:
        ),
        now: created_at + 1
      )
    end.to raise_error(
      Karya::InvalidQueueStoreOperationError,
      'Redis queue-store snapshots do not support Symbol job arguments'
    )

    store.enqueue(job: submission_job(id: 'job-valid'), now: created_at + 2)

    reservation = store.reserve(queue: 'billing', worker_id: 'worker-after-failure', lease_duration: 60, now: created_at + 3)

    expect(reservation&.job_id).to eq('job-valid')
  end

  it 'swallows reload errors while restoring authoritative state after a persistence failure' do
    journal_support = store.send(:journal_support)

    allow(journal_support).to receive(:load_persisted_state).and_raise(StandardError, 'reload failed')

    expect(journal_support.send(:restore_authoritative_state_after_failure)).to be_nil
  end

  it 'retries distributed lock acquisition until Redis grants the lock' do
    polling_client = Class.new(fake_redis_client_class) do
      def set(key, value, **options)
        return super unless options.fetch(:nx, false)

        @set_calls ||= 0
        @set_calls += 1
        return nil if @set_calls == 1

        data[key] = value
        'OK'
      end
    end.new
    allow(Redis).to receive(:new).with(url: redis_url).and_return(polling_client)

    described_class.new(url: redis_url, namespace: 'polling').enqueue(
      job: submission_job(id: 'job-polling'),
      now: created_at + 1
    )

    expect(polling_client.data.fetch('polling:queue_store:version')).to eq('1')
    expect(polling_client.data).to have_key('polling:queue_store:event:1')
    expect(polling_client.data).not_to have_key('polling:queue_store:lock')
  end

  it 'does not delete another process lock during eval fallback cleanup' do
    guarded_client = fake_redis_client_class.new
    allow(Redis).to receive(:new).with(url: redis_url).and_return(guarded_client)
    guarded_store = described_class.new(url: redis_url, namespace: 'guarded')
    allow(guarded_client).to receive(:eval).and_wrap_original do |original, script, keys:, argv:|
      raise 'boom' if script == persistence_mutex_class::RELEASE_SCRIPT

      original.call(script, keys:, argv:)
    end
    allow(guarded_client).to receive(:del).and_call_original

    expect do
      guarded_store.enqueue(job: submission_job(id: 'job-guarded'), now: created_at + 1)
    end.not_to raise_error

    expect(guarded_client).not_to have_received(:del).with('guarded:queue_store:lock')
  end

  it 'compacts hot-path journal entries into a snapshot baseline' do
    mutex = store.instance_variable_get(:@mutex)
    journal_support = store.send(:journal_support)

    journal_support.instance_variable_set(:@loaded_version, described_class::HOT_PATH_COMPACTION_THRESHOLD)
    journal_support.instance_variable_set(:@snapshot_version, 0)
    mutex.instance_variable_set(:@current_lock_token, 'token-compact')
    redis_client.data["#{namespace}:queue_store:lock"] = 'token-compact'
    redis_client.data["#{namespace}:queue_store:event:1"] = 'event-1'

    store.send(:compact_snapshot_if_needed)

    expect(journal_support.instance_variable_get(:@snapshot_version)).to eq(described_class::HOT_PATH_COMPACTION_THRESHOLD)
    expect(redis_client.data).to have_key("#{namespace}:queue_store:state")
    expect(redis_client.data).not_to have_key("#{namespace}:queue_store:event:1")
  end

  it 'compacts hot-path journal entries automatically after event persistence reaches the threshold' do
    stub_const("#{described_class}::HOT_PATH_COMPACTION_THRESHOLD", 1)

    store.enqueue(job: submission_job(id: 'job-compact-auto'), now: created_at + 1)

    expect(redis_client.data).to have_key("#{namespace}:queue_store:state")
    expect(redis_client.data).not_to have_key("#{namespace}:queue_store:event:1")
  end

  it 'returns early from journal compaction when the hot-path backlog is below the compaction threshold' do
    mutex = store.instance_variable_get(:@mutex)
    journal_support = store.send(:journal_support)

    journal_support.instance_variable_set(:@loaded_version, described_class::HOT_PATH_COMPACTION_THRESHOLD - 1)
    journal_support.remove_instance_variable(:@snapshot_version) if journal_support.instance_variable_defined?(:@snapshot_version)
    allow(mutex).to receive(:compact_snapshot)

    store.send(:compact_snapshot_if_needed)

    expect(mutex).not_to have_received(:compact_snapshot)
  end

  it 'returns early from journal compaction before any journal version has been loaded' do
    mutex = store.instance_variable_get(:@mutex)

    allow(mutex).to receive(:compact_snapshot)

    store.send(:compact_snapshot_if_needed)

    expect(mutex).not_to have_received(:compact_snapshot)
  end

  it 'keeps journal entries when snapshot compaction does not obtain a persisted snapshot write' do
    mutex = store.instance_variable_get(:@mutex)
    journal_support = store.send(:journal_support)

    journal_support.instance_variable_set(:@loaded_version, described_class::HOT_PATH_COMPACTION_THRESHOLD)
    journal_support.instance_variable_set(:@snapshot_version, 0)
    redis_client.data["#{namespace}:queue_store:event:1"] = 'event-1'
    allow(mutex).to receive(:compact_snapshot).and_return(false)

    store.send(:compact_snapshot_if_needed)

    expect(redis_client.data).to have_key("#{namespace}:queue_store:event:1")
  end

  it 'deletes only the journal range created since the previous snapshot baseline' do
    mutex = store.instance_variable_get(:@mutex)
    journal_support = store.send(:journal_support)

    previous_snapshot_version = described_class::HOT_PATH_COMPACTION_THRESHOLD
    journal_support.instance_variable_set(:@loaded_version, previous_snapshot_version + described_class::HOT_PATH_COMPACTION_THRESHOLD)
    journal_support.instance_variable_set(:@snapshot_version, previous_snapshot_version)
    mutex.instance_variable_set(:@current_lock_token, 'token-compact-range')
    redis_client.data["#{namespace}:queue_store:lock"] = 'token-compact-range'
    redis_client.data["#{namespace}:queue_store:event:1"] = 'event-1'
    redis_client.data["#{namespace}:queue_store:event:#{previous_snapshot_version + 1}"] = 'event-new'

    store.send(:compact_snapshot_if_needed)

    expect(redis_client.data).to have_key("#{namespace}:queue_store:event:1")
    expect(redis_client.data).not_to have_key("#{namespace}:queue_store:event:#{previous_snapshot_version + 1}")
  end

  it 'skips journal deletion when the computed prune range is empty' do
    journal_support = store.send(:journal_support)

    allow(redis_client).to receive(:del).and_call_original

    journal_support.send(:delete_journal_events_between, 2, 1)

    expect(redis_client).not_to have_received(:del)
  end
end
