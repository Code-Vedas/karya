# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Worker, :integration do
  let(:queue_store) { Karya::QueueStore::InMemory.new(token_generator: -> { 'lease-token' }) }
  let(:worker_id) { 'worker-1' }
  let(:queue_name) { 'billing' }
  let(:base_time) { Time.utc(2026, 4, 7, 12, 0, 0) }
  let(:current_time) { [base_time, base_time + 1, base_time + 2, base_time + 3].each }

  def enqueue_submission_job(id:, handler: 'billing_sync')
    queue_store.enqueue(
      job: Karya::Job.new(
        id:,
        queue: queue_name,
        handler:,
        arguments: { 'account_id' => 42 },
        state: :submission,
        created_at: base_time
      ),
      now: base_time
    )
  end

  def stored_job(job_id)
    queue_store.instance_variable_get(:@state).jobs_by_id.fetch(job_id)
  end

  it 'executes a queued job to succeeded through the real worker and queue-store path' do
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
        'billing_sync' => lambda do |**_arguments|
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
end
