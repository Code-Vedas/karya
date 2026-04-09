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

  it 'executes an eligible lower-priority job when a higher-priority job is concurrency-blocked' do
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
        id: 'job-eligible',
        queue: queue_name,
        handler: 'billing_sync',
        arguments: { 'account_id' => 42 },
        priority: 1,
        state: :submission,
        created_at: base_time + 1
      ),
      now: base_time + 1
    )

    first_reservation = constrained_store.reserve(queue: queue_name, worker_id: worker_id, lease_duration: 30, now: base_time + 2)
    worker_clock = [base_time + 3, base_time + 4, base_time + 5, base_time + 6].each
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
    expect(state.jobs_by_id.fetch('job-eligible').state).to eq(:succeeded)
  end
end
