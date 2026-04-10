# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Worker, :integration do
  let(:queue_store) { Karya::QueueStore::InMemory.new(token_generator: -> { 'lease-token' }, policy_set:) }
  let(:worker_id) { 'worker-1' }
  let(:queue_name) { 'billing' }
  let(:base_time) { Time.utc(2026, 4, 7, 12, 0, 0) }
  let(:current_time) { [base_time, base_time + 1, base_time + 2, base_time + 3].each }
  let(:policy_set) { Karya::Backpressure::PolicySet.new }
  let(:retry_policy) { Karya::RetryPolicy.new(max_attempts: 3, base_delay: 5, multiplier: 2) }

  def enqueue_submission_job(id:, handler: 'billing_sync', priority: 0, concurrency_key: nil, rate_limit_key: nil)
    queue_store.enqueue(
      job: Karya::Job.new(
        id:,
        queue: queue_name,
        handler:,
        arguments: { 'account_id' => 42 },
        priority:,
        concurrency_key:,
        rate_limit_key:,
        state: :submission,
        created_at: base_time
      ),
      now: base_time
    )
  end

  def stored_job(job_id)
    queue_store.instance_variable_get(:@state).jobs_by_id.fetch(job_id)
  end

  it 'executes a queued job to succeed through the real worker and queue-store path' do
    enqueue_submission_job(id: 'job-success')

    worker = described_class.new(
      queue_store:,
      worker_id:,
      queues: [queue_name],
      handlers: {
        'billing_sync' => lambda do |account_id:|
          expect(account_id).to eq(42)
        end
      },
      lease_duration: 30,
      clock: -> { current_time.next }
    )

    result = worker.work_once

    expect(result.state).to eq(:succeeded)
    expect(result.attempt).to eq(1)
    expect(stored_job('job-success').state).to eq(:succeeded)
  end

  it 'fails a queued job when the handler raises and persists the failed terminal state' do
    enqueue_submission_job(id: 'job-failure')

    worker = described_class.new(
      queue_store:,
      worker_id:,
      queues: [queue_name],
      handlers: {
        'billing_sync' => lambda do |account_id:|
          expect(account_id).to eq(42)
          raise 'boom'
        end
      },
      lease_duration: 30,
      clock: -> { current_time.next }
    )

    result = worker.work_once

    expect(result.state).to eq(:failed)
    expect(result.attempt).to eq(1)
    expect(stored_job('job-failure').state).to eq(:failed)
  end

  it 'uses worker retry policy to move failed work into retry_pending and later succeed on retry' do
    enqueue_submission_job(id: 'job-retry')
    invocation_count = 0
    retrying_clock = [
      base_time + 1,
      base_time + 2,
      base_time + 3,
      base_time + 8,
      base_time + 9,
      base_time + 10
    ].each
    worker = described_class.new(
      queue_store: queue_store,
      worker_id: worker_id,
      queues: [queue_name],
      handlers: {
        'billing_sync' => lambda do |account_id:|
          invocation_count += 1
          expect(account_id).to eq(42)
          raise 'boom' if invocation_count == 1
        end
      },
      lease_duration: 30,
      retry_policy: retry_policy,
      clock: -> { retrying_clock.next }
    )

    first_result = worker.work_once
    second_result = worker.work_once

    expect(first_result.state).to eq(:retry_pending)
    expect(first_result.next_retry_at).to eq(base_time + 8)
    expect(first_result.attempt).to eq(1)
    expect(second_result.attempt).to eq(2)
    expect(second_result.state).to eq(:succeeded)
    expect(stored_job('job-retry').state).to eq(:succeeded)
  end

  it 'prefers job retry policy over worker retry policy' do
    queue_store.enqueue(
      job: Karya::Job.new(
        id: 'job-job-policy',
        queue: queue_name,
        handler: 'billing_sync',
        arguments: { 'account_id' => 42 },
        retry_policy: Karya::RetryPolicy.new(max_attempts: 2, base_delay: 9, multiplier: 2),
        state: :submission,
        created_at: base_time
      ),
      now: base_time
    )
    job_clock = [base_time + 1, base_time + 2, base_time + 3].each
    worker = described_class.new(
      queue_store: queue_store,
      worker_id: worker_id,
      queues: [queue_name],
      handlers: { 'billing_sync' => ->(account_id:) { raise 'boom' if account_id == 42 } },
      lease_duration: 30,
      retry_policy: retry_policy,
      clock: -> { job_clock.next }
    )

    result = worker.work_once

    expect(result.state).to eq(:retry_pending)
    expect(result.next_retry_at).to eq(base_time + 12)
    expect(stored_job('job-job-policy').retry_policy.max_attempts).to eq(2)
  end

  it 'executes an eligible lower-priority job when a queued higher-priority job is concurrency-blocked' do
    constrained_store = Karya::QueueStore::InMemory.new(
      token_generator: -> { 'lease-token' },
      policy_set: Karya::Backpressure::PolicySet.new(concurrency: { account_sync: { limit: 1 } })
    )
    constrained_store.enqueue(
      job: Karya::Job.new(
        id: 'job-blocked',
        queue: queue_name,
        handler: 'billing_sync',
        arguments: { 'account_id' => 42 },
        priority: 10,
        concurrency_key: 'account_sync',
        state: :submission,
        created_at: base_time
      ),
      now: base_time
    )
    constrained_store.enqueue(
      job: Karya::Job.new(
        id: 'job-blocked-queued',
        queue: queue_name,
        handler: 'billing_sync',
        arguments: { 'account_id' => 42 },
        priority: 9,
        concurrency_key: 'account_sync',
        state: :submission,
        created_at: base_time + 1
      ),
      now: base_time + 1
    )
    constrained_store.enqueue(
      job: Karya::Job.new(
        id: 'job-eligible',
        queue: queue_name,
        handler: 'billing_sync',
        arguments: { 'account_id' => 42 },
        priority: 1,
        state: :submission,
        created_at: base_time + 2
      ),
      now: base_time + 2
    )

    first_reservation = constrained_store.reserve(queue: queue_name, worker_id: worker_id, lease_duration: 30, now: base_time + 3)
    worker_clock = [base_time + 4, base_time + 5, base_time + 6, base_time + 7].each
    worker = described_class.new(
      queue_store: constrained_store,
      worker_id: 'worker-2',
      queues: [queue_name],
      handlers: { 'billing_sync' => ->(account_id:) { expect(account_id).to eq(42) } },
      lease_duration: 30,
      clock: -> { worker_clock.next }
    )

    result = worker.work_once
    state = constrained_store.instance_variable_get(:@state)

    expect(first_reservation.job_id).to eq('job-blocked')
    expect(result.id).to eq('job-eligible')
    expect(state.jobs_by_id.fetch('job-blocked').state).to eq(:reserved)
    expect(state.jobs_by_id.fetch('job-blocked-queued').state).to eq(:queued)
    expect(state.jobs_by_id.fetch('job-eligible').state).to eq(:succeeded)
  end
end
