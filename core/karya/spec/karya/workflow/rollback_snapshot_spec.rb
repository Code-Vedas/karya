# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Workflow::RollbackSnapshot do
  let(:requested_at) { Time.utc(2026, 4, 24, 12, 0, 0) }

  it 'builds immutable rollback metadata and allows no-op compensation' do
    snapshot = described_class.new(
      workflow_batch_id: ' batch_1 ',
      rollback_batch_id: ' batch_1.rollback ',
      reason: 'operator rollback',
      requested_at:,
      compensation_job_ids: []
    )

    expect(snapshot).to have_attributes(
      workflow_batch_id: 'batch_1',
      rollback_batch_id: 'batch_1.rollback',
      reason: 'operator rollback',
      requested_at:,
      compensation_job_ids: [],
      compensation_count: 0
    )
    expect(snapshot).to be_frozen
    expect(snapshot.compensation_job_ids).to be_frozen
  end

  it 'normalizes compensation job ids' do
    snapshot = described_class.new(
      workflow_batch_id: 'batch_1',
      rollback_batch_id: :'batch_1.rollback',
      reason: 'operator rollback',
      requested_at:,
      compensation_job_ids: [:first, ' second ']
    )

    expect(snapshot.compensation_job_ids).to eq(%w[first second])
    expect(snapshot.compensation_count).to eq(2)
  end

  it 'rejects invalid rollback metadata' do
    expect do
      described_class.new(
        workflow_batch_id: nil,
        rollback_batch_id: :'batch_1.rollback',
        reason: 'operator rollback',
        requested_at:,
        compensation_job_ids: []
      )
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'workflow_batch_id must be present')

    expect do
      described_class.new(
        workflow_batch_id: 'batch_1',
        rollback_batch_id: nil,
        reason: 'operator rollback',
        requested_at:,
        compensation_job_ids: []
      )
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'rollback_batch_id must be present')

    expect do
      described_class.new(
        workflow_batch_id: 'batch_1',
        rollback_batch_id: :'batch_1.rollback',
        reason: '',
        requested_at:,
        compensation_job_ids: []
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'reason must be present')

    expect do
      described_class.new(
        workflow_batch_id: 'batch_1',
        rollback_batch_id: :'batch_1.rollback',
        reason: 'operator rollback',
        requested_at: 'now',
        compensation_job_ids: []
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'requested_at must be a Time')

    expect do
      described_class.new(
        workflow_batch_id: 'batch_1',
        rollback_batch_id: :'batch_1.rollback',
        reason: 'operator rollback',
        requested_at:,
        compensation_job_ids: 'rollback-job-1'
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'compensation_job_ids must be an Array')
  end

  it 'rejects duplicate compensation job ids after normalization' do
    expect do
      described_class.new(
        workflow_batch_id: 'batch_1',
        rollback_batch_id: :'batch_1.rollback',
        reason: 'operator rollback',
        requested_at:,
        compensation_job_ids: ['rollback_job_1', ' rollback_job_1 ']
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'duplicate compensation job id "rollback_job_1"')
  end
end
