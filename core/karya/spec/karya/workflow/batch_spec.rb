# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Workflow::Batch do
  let(:created_at) { Time.utc(2026, 4, 24, 12, 0, 0) }

  it 'normalizes immutable batch identity and membership' do
    batch = described_class.new(
      id: ' billing-closeout ',
      job_ids: [' step_1 ', 'step_2'],
      created_at: created_at
    )

    expect(batch).to have_attributes(
      id: 'billing-closeout',
      job_ids: %w[step_1 step_2],
      created_at: created_at,
      updated_at: created_at
    )
    expect(batch).to be_frozen
    expect(batch.job_ids).to be_frozen
  end

  it 'rejects empty membership' do
    expect do
      described_class.new(id: 'batch_1', job_ids: [], created_at:)
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'batch must include at least one job')
  end

  it 'raises batch-domain errors for invalid batch ids' do
    expect do
      described_class.new(id: nil, job_ids: ['job_1'], created_at:)
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'batch_id must be present')
  end

  it 'rejects non-array membership' do
    expect do
      described_class.new(id: 'batch_1', job_ids: 'job_1', created_at:)
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'job_ids must be an Array')
  end

  it 'rejects invalid max size' do
    expect do
      described_class.new(id: 'batch_1', job_ids: ['job_1'], created_at:, max_size: 0)
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'max_size must be a positive Integer')
  end

  it 'rejects duplicate job ids after normalization' do
    expect do
      described_class.new(id: 'batch_1', job_ids: [' step_1 ', 'step_1'], created_at:)
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'duplicate batch job id "step_1"')
  end

  it 'raises batch-domain errors for invalid member job ids' do
    expect do
      described_class.new(id: 'batch_1', job_ids: [nil], created_at:)
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'job_id must be present')
  end

  it 'rejects oversize membership' do
    expect do
      described_class.new(id: 'batch_1', job_ids: %w[step_1 step_2], created_at:, max_size: 1)
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'batch size must be at most 1 job')
    expect do
      described_class.new(id: 'batch_1', job_ids: %w[step_1 step_2 step_3], created_at:, max_size: 2)
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'batch size must be at most 2 jobs')
  end

  it 'validates timestamps' do
    expect do
      described_class.new(id: 'batch_1', job_ids: ['step_1'], created_at: 'now')
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'created_at must be a Time')
  end
end
