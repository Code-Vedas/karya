# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::RecoveryReport do
  let(:recovered_at) { Time.utc(2026, 3, 27, 12, 0, 0) }
  let(:expired_job) { job(id: 'expired') }
  let(:reserved_job) { job(id: 'reserved') }
  let(:running_job) { job(id: 'running') }

  def job(id:)
    Karya::Job.new(
      id:,
      queue: 'billing',
      handler: 'billing_sync',
      state: :queued,
      created_at: recovered_at
    )
  end

  it 'freezes defensive copies and exposes jobs in recovery order' do
    expired_jobs = [expired_job]
    report = described_class.new(
      recovered_at:,
      expired_jobs:,
      recovered_reserved_jobs: [reserved_job],
      recovered_running_jobs: [running_job]
    )
    expired_jobs.clear

    expect(report).to be_frozen
    expect(report.recovered_at).to eq(recovered_at)
    expect(report.recovered_at).to be_frozen
    expect(report.expired_jobs).to eq([expired_job])
    expect(report.expired_jobs).to be_frozen
    expect(report.jobs).to be_frozen
    expect(report.recovered_jobs).to be_frozen
    expect(report.jobs).to eq([expired_job, reserved_job, running_job])
    expect(report.recovered_jobs).to eq([reserved_job, running_job])
    combined_jobs = report.jobs
    combined_recovered_jobs = report.recovered_jobs
    expect(report.jobs.object_id).to eq(combined_jobs.object_id)
    expect(report.recovered_jobs.object_id).to eq(combined_recovered_jobs.object_id)
  end

  it 'rejects invalid recovered_at values' do
    expect do
      described_class.new(
        recovered_at: 'later',
        expired_jobs: [],
        recovered_reserved_jobs: [],
        recovered_running_jobs: []
      )
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'recovered_at must be a Time')
  end

  it 'rejects non-array job groups' do
    expect do
      described_class.new(
        recovered_at:,
        expired_jobs: nil,
        recovered_reserved_jobs: [],
        recovered_running_jobs: []
      )
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'expired_jobs must be an Array')
  end

  it 'rejects non-job entries' do
    expect do
      described_class.new(
        recovered_at:,
        expired_jobs: ['not-a-job'],
        recovered_reserved_jobs: [],
        recovered_running_jobs: []
      )
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'expired_jobs entries must be Karya::Job')
  end
end
