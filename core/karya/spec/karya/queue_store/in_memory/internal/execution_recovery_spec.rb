# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::ExecutionRecovery' do
  let(:described_class) do
    Karya::QueueStore::InMemory.const_get(:Internal, false).const_get(:ExecutionRecovery, false)
  end
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }

  it 'rebuilds a running job as queued with the recovery timestamp' do
    running_job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      state: :running,
      created_at:,
      updated_at: created_at + 1
    )

    queued_job = described_class.new(running_job, created_at + 5).to_queued_job

    expect(queued_job.state).to eq(:queued)
    expect(queued_job.updated_at).to eq(created_at + 5)
  end
end
