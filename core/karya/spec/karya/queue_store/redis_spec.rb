# frozen_string_literal: true

RSpec.describe Karya::QueueStore::Redis do
  subject(:store) { described_class.new(url: redis_url, namespace:) }

  let(:redis_url) { 'redis://example.test:6379/0' }
  let(:created_at) { Time.utc(2026, 5, 5, 12, 0, 0) }
  let(:namespace) { 'redis-unit' }
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

      def expire(key, _seconds)
        data.key?(key) ? 1 : 0
      end

      def eval(_script, keys:, argv:)
        raise eval_error if eval_error

        key = keys.fetch(0)
        token = argv.fetch(0)
        return 0 unless get(key) == token

        del(key)
      end

      private

      attr_reader :eval_error
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
    expect(redis_client.data).to have_key('redis-unit:queue_store:state')
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

  it 'cleans up the distributed lock when eval fallback is needed' do
    fallback_client = fake_redis_client_class.new(eval_error: RuntimeError.new('boom'))
    allow(Redis).to receive(:new).with(url: redis_url).and_return(fallback_client)
    fallback_store = described_class.new(url: redis_url, namespace: 'fallback')

    fallback_store.enqueue(job: submission_job(id: 'job-fallback'), now: created_at + 1)

    expect(fallback_client.data).not_to have_key('fallback:queue_store:lock')
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

    expect(polling_client.data).to have_key('polling:queue_store:state')
    expect(polling_client.data).not_to have_key('polling:queue_store:lock')
  end

  it 'does not delete another process lock during eval fallback cleanup' do
    guarded_client = fake_redis_client_class.new(eval_error: RuntimeError.new('boom'))
    allow(Redis).to receive(:new).with(url: redis_url).and_return(guarded_client)
    guarded_store = described_class.new(url: redis_url, namespace: 'guarded')
    allow(guarded_client).to receive(:del).and_call_original
    allow(guarded_client).to receive(:get).and_call_original
    allow(guarded_client).to receive(:get).with('guarded:queue_store:lock').and_return('different-token')

    guarded_store.enqueue(job: submission_job(id: 'job-guarded'), now: created_at + 1)

    expect(guarded_client).not_to have_received(:del).with('guarded:queue_store:lock')
  end
end
