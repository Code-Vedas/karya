# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::RetrySupport' do
  subject(:store) { store_class.new }

  let(:store_class) { Karya::QueueStore::InMemory }
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }

  def store_state
    store.instance_variable_get(:@state)
  end

  it 'promotes due retry-pending jobs back to queued' do
    retry_job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      state: :retry_pending,
      created_at:,
      updated_at: created_at + 1,
      next_retry_at: created_at + 2
    )
    store.send(:store_job, job: retry_job)
    store_state.register_retry_pending(retry_job.id)

    store.send(:promote_due_retry_pending_jobs, created_at + 3)

    expect(store_state.jobs_by_id.fetch('job-1').state).to eq(:queued)
    expect(store_state.retry_pending_job_ids).to eq([])
  end
end
