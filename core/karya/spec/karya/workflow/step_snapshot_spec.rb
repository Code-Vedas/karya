# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Workflow::StepSnapshot do
  let(:created_at) { Time.utc(2026, 4, 24, 12, 0, 0) }

  around do |example|
    Karya::JobLifecycle.send(:clear_extensions!)
    example.run
    Karya::JobLifecycle.send(:clear_extensions!)
  end

  def job(id: 'job-child', state: :queued)
    Karya::Job.new(id:, queue: :billing, handler: :sync_billing, state:, created_at:)
  end

  def snapshot(state: :queued, prerequisite_states: { 'job-root' => :succeeded })
    described_class.new(
      workflow_id: ' invoice_closeout ',
      batch_id: ' batch_1 ',
      step_id: ' child ',
      job_id: ' job-child ',
      job: job(state:),
      prerequisite_job_ids: [' job-root '],
      prerequisite_states:
    )
  end

  it 'builds immutable per-step inspection data' do
    result = snapshot

    expect(result).to have_attributes(
      workflow_id: 'invoice_closeout',
      batch_id: 'batch_1',
      step_id: 'child',
      job_id: 'job-child',
      state: :queued,
      prerequisite_job_ids: ['job-root'],
      prerequisite_states: { 'job-root' => :succeeded }
    )
    expect(result).to be_ready
    expect(result).not_to be_blocked
    expect(result).not_to be_active
    expect(result).not_to be_terminal
    expect(result).to be_frozen
    expect(result.prerequisite_job_ids).to be_frozen
    expect(result.prerequisite_states).to be_frozen
  end

  it 'derives blocked, active, and terminal state' do
    expect(snapshot(prerequisite_states: { 'job-root' => :queued })).to be_blocked
    expect(snapshot(prerequisite_states: {})).to be_blocked
    expect(snapshot(state: :running)).to be_active
    expect(snapshot(state: :succeeded)).to be_terminal
  end

  it 'treats custom nonterminal lifecycle states as active' do
    Karya::JobLifecycle.register_state(:awaiting_review)

    expect(snapshot(state: :awaiting_review)).to be_active
  end

  it 'validates job and prerequisite membership' do
    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: :batch,
        step_id: :child,
        job_id: :other,
        job: job,
        prerequisite_job_ids: [],
        prerequisite_states: {}
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'job_id must match job id')

    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: :batch,
        step_id: :child,
        job_id: :'job-child',
        job: 'job-child',
        prerequisite_job_ids: [],
        prerequisite_states: {}
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'job must be Karya::Job')

    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: :batch,
        step_id: :child,
        job_id: :'job-child',
        job: job,
        prerequisite_job_ids: ['job-root'],
        prerequisite_states: { 'job-other' => :succeeded }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'unknown prerequisite job "job-other"')
  end

  it 'validates prerequisite id collections and state maps' do
    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: :batch,
        step_id: :child,
        job_id: :'job-child',
        job: job,
        prerequisite_job_ids: [],
        prerequisite_states: {},
        unexpected: true
      )
    end.to raise_error(ArgumentError, 'unknown keyword: :unexpected')

    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: :batch,
        step_id: :child,
        job_id: :'job-child',
        job: job,
        prerequisite_job_ids: 'job-root',
        prerequisite_states: {}
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'prerequisite_job_ids must be an Array')

    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: :batch,
        step_id: :child,
        job_id: :'job-child',
        job: job,
        prerequisite_job_ids: %w[job-root job-root],
        prerequisite_states: {}
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'duplicate prerequisite_job_id "job-root"')

    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: :batch,
        step_id: :child,
        job_id: :'job-child',
        job: job,
        prerequisite_job_ids: ['job-root'],
        prerequisite_states: 'job-root'
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'prerequisite_states must be a Hash')
  end

  it 'rejects duplicate normalized prerequisite job ids' do
    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: :batch,
        step_id: :child,
        job_id: :'job-child',
        job: job,
        prerequisite_job_ids: ['job-root'],
        prerequisite_states: { ' job-root ' => :queued, 'job-root' => :succeeded }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'duplicate prerequisite job "job-root"')
  end

  it 'rejects invalid prerequisite state values' do
    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: :batch,
        step_id: :child,
        job_id: :'job-child',
        job: job,
        prerequisite_job_ids: ['job-root'],
        prerequisite_states: { 'job-root' => ' not-a-state ' }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'Unknown job state: "not_a_state"')
  end

  it 'normalizes prerequisite state values and allows nil' do
    result = snapshot(prerequisite_states: { ' job-root ' => ' SUCCEEDED ' })
    missing = snapshot(prerequisite_states: { ' job-root ' => nil })

    expect(result.prerequisite_states).to eq('job-root' => :succeeded)
    expect(missing.prerequisite_states).to eq('job-root' => nil)
  end
end
