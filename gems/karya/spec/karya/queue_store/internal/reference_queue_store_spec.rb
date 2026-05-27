# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../../../lib/karya/queue_store/internal/reference_queue_store'

RSpec.describe Karya::QueueStore::Internal::ReferenceQueueStore do
  let(:now) { Time.utc(2026, 5, 23, 12, 0, 0) }

  def submission_job(id:)
    Karya::Job.new(
      id:,
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :submission,
      created_at: now,
      updated_at: now
    )
  end

  it 'returns nil durable reserve candidates and supports reserve deletion without an index' do
    store = Karya::QueueStore::InMemory.new(token_generator: -> { 'token' })
    queued_job = store.enqueue(job: submission_job(id: 'job-1'), now:)
    state = store.instance_variable_get(:@state)
    state.queued_job_ids_by_queue['billing'] = ['job-1']
    state.jobs_by_id['job-1'] = queued_job

    expect(store.send(:durable_reserve_candidate_job_ids_for_queue, queue: 'billing', now:)).to be_nil

    reservation = store.send(
      :reserve_job,
      matched_queue: 'billing',
      matched_job_id: 'job-1',
      matched_job_index: nil,
      worker_id: 'worker-1',
      lease_duration: 30,
      queues: ['billing'],
      subscription_key: 'sub',
      now:
    )

    expect(reservation).to have_attributes(job_id: 'job-1', worker_id: 'worker-1')
    expect(state.queued_job_ids_by_queue).to be_empty
  end
end
