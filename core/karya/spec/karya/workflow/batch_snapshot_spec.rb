# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Workflow::BatchSnapshot do
  let(:captured_at) { Time.utc(2026, 4, 24, 12, 0, 0) }

  around do |example|
    Karya::JobLifecycle.send(:clear_extensions!)
    example.run
    Karya::JobLifecycle.send(:clear_extensions!)
  end

  def job(id:, state:)
    Karya::Job.new(id:, queue: :billing, handler: :sync_billing, state:, created_at: captured_at)
  end

  def aggregate_state_for(state)
    described_class.new(
      batch_id: :batch,
      captured_at:,
      job_ids: ['job_1'],
      jobs: [job(id: 'job_1', state:)]
    ).aggregate_state
  end

  it 'builds an immutable aggregate snapshot' do
    jobs = [
      job(id: 'job_1', state: :succeeded),
      job(id: 'job_2', state: :cancelled)
    ]

    snapshot = described_class.new(batch_id: 'batch_1', captured_at:, job_ids: %w[job_1 job_2], jobs:)

    expect(snapshot).to have_attributes(
      batch_id: 'batch_1',
      job_ids: %w[job_1 job_2],
      jobs: jobs,
      state_counts: { succeeded: 1, cancelled: 1 },
      total_count: 2,
      completed_count: 2,
      failed_count: 0,
      aggregate_state: :completed
    )
    expect(snapshot).to be_frozen
    expect(snapshot.jobs).to be_frozen
    expect(snapshot.state_counts).to be_frozen
  end

  it 'keeps membership validation private' do
    snapshot = described_class.new(
      batch_id: 'batch_1',
      captured_at:,
      job_ids: ['job_1'],
      jobs: [job(id: 'job_1', state: :queued)]
    )

    expect(snapshot.private_methods).to include(:validate_membership)
    expect(snapshot.public_methods).not_to include(:validate_membership)
  end

  it 'raises batch-domain errors for invalid identifiers' do
    expect do
      described_class.new(batch_id: nil, captured_at:, job_ids: ['job_1'], jobs: [job(id: 'job_1', state: :queued)])
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'batch_id must be present')

    expect do
      described_class.new(batch_id: 'batch_1', captured_at:, job_ids: [nil], jobs: [job(id: 'job_1', state: :queued)])
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'job_id must be present')
  end

  it 'derives aggregate state from member jobs' do
    expect(aggregate_state_for(:failed)).to eq(:failed)
    expect(aggregate_state_for(:dead_letter)).to eq(:failed)
    expect(aggregate_state_for(:queued)).to eq(:running)
    expect(aggregate_state_for(:retry_pending)).to eq(:running)
    expect(aggregate_state_for(:succeeded)).to eq(:succeeded)
    expect(aggregate_state_for(:cancelled)).to eq(:cancelled)
  end

  it 'treats custom nonterminal lifecycle states as running' do
    Karya::JobLifecycle.register_state(:awaiting_review)
    custom_job = job(id: 'job_1', state: :awaiting_review)

    snapshot = described_class.new(
      batch_id: 'batch_1',
      captured_at:,
      job_ids: ['job_1'],
      jobs: [custom_job]
    )

    expect(snapshot.aggregate_state).to eq(:running)
  end

  it 'rejects mismatched job ids and jobs' do
    expect do
      described_class.new(
        batch_id: 'batch_1',
        captured_at:,
        job_ids: %w[job_1 job_2],
        jobs: [job(id: 'job_1', state: :queued), job(id: 'job_3', state: :queued)]
      )
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'job_ids must match jobs in order')
  end

  it 'validates captured time' do
    expect do
      described_class.new(batch_id: 'batch_1', captured_at: 'now', job_ids: ['job_1'], jobs: [job(id: 'job_1', state: :queued)])
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'captured_at must be a Time')
  end

  it 'validates job id input' do
    expect do
      described_class.new(batch_id: 'batch_1', captured_at:, job_ids: 'job_1', jobs: [job(id: 'job_1', state: :queued)])
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'job_ids must be an Array')

    expect do
      described_class.new(batch_id: 'batch_1', captured_at:, job_ids: [], jobs: [job(id: 'job_1', state: :queued)])
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'batch snapshot must include at least one job id')

    expect do
      described_class.new(
        batch_id: 'batch_1',
        captured_at:,
        job_ids: %w[job_1 job_1],
        jobs: [job(id: 'job_1', state: :queued), job(id: 'job_1', state: :queued)]
      )
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'duplicate batch job id "job_1"')
  end

  it 'validates job list input' do
    expect do
      described_class.new(batch_id: 'batch_1', captured_at:, job_ids: ['job_1'], jobs: 'job_1')
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'jobs must be an Array')

    expect do
      described_class.new(batch_id: 'batch_1', captured_at:, job_ids: ['job_1'], jobs: [])
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'batch snapshot must include at least one job')
  end

  it 'rejects invalid job entries' do
    expect do
      described_class.new(batch_id: 'batch_1', captured_at:, job_ids: ['job_1'], jobs: ['job_1'])
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'jobs entries must be Karya::Job')
  end
end
