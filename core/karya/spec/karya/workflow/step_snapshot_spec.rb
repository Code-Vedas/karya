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

  def snapshot(
    state: :queued,
    prerequisite_states: { 'job-root' => :succeeded },
    interaction_kind: nil,
    interaction_name: nil,
    interaction_received_at: nil
  )
    described_class.new(
      workflow_id: ' invoice_closeout ',
      batch_id: ' batch_1 ',
      step_id: ' child ',
      job_id: ' job-child ',
      job: job(state:),
      prerequisite_job_ids: [' job-root '],
      prerequisite_states:,
      interaction_kind:,
      interaction_name:,
      interaction_received_at:
    )
  end

  def child_workflow(state)
    Karya::Workflow::ChildWorkflowSnapshot.new(
      parent_workflow_id: :invoice_closeout,
      parent_batch_id: 'batch_1',
      parent_step_id: :child,
      parent_job_id: :'job-child',
      child_workflow_id: :payment,
      child_batch_id: :payment_batch,
      child_state: state
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

  it 'blocks waiting steps until their required interaction arrives' do
    blocked = snapshot(interaction_kind: :signal, interaction_name: :manager_approved)
    ready = snapshot(
      interaction_kind: :event,
      interaction_name: :payment_received,
      interaction_received_at: created_at + 1
    )

    expect(blocked).to be_blocked
    expect(ready).to be_ready
    expect(ready).to have_attributes(
      interaction_kind: :event,
      interaction_name: 'payment_received',
      interaction_received_at: created_at + 1
    )
  end

  it 'blocks child workflow steps until the child workflow succeeds' do
    missing_child = described_class.new(
      workflow_id: :invoice_closeout,
      batch_id: 'batch_1',
      step_id: :child,
      job_id: :'job-child',
      job: job,
      prerequisite_job_ids: [],
      prerequisite_states: {},
      child_workflow_id: :payment
    )
    running_child = described_class.new(
      workflow_id: :invoice_closeout,
      batch_id: 'batch_1',
      step_id: :child,
      job_id: :'job-child',
      job: job,
      prerequisite_job_ids: [],
      prerequisite_states: {},
      child_workflow_id: :payment,
      child_workflow: child_workflow(:running)
    )
    succeeded_child = described_class.new(
      workflow_id: :invoice_closeout,
      batch_id: 'batch_1',
      step_id: :child,
      job_id: :'job-child',
      job: job,
      prerequisite_job_ids: [],
      prerequisite_states: {},
      child_workflow_id: :payment,
      child_workflow: child_workflow(:succeeded)
    )

    expect(missing_child).to be_child_workflow
    expect(missing_child).to be_blocked
    expect(running_child).to be_blocked
    expect(succeeded_child).to be_ready
  end

  it 'validates child workflow relationship metadata' do
    common_attributes = {
      workflow_id: :invoice_closeout,
      batch_id: 'batch_1',
      step_id: :child,
      job_id: :'job-child',
      job: job,
      prerequisite_job_ids: [],
      prerequisite_states: {},
      child_workflow_id: :payment
    }

    expect do
      described_class.new(**common_attributes, child_workflow: 'payment')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'child_workflow must be Karya::Workflow::ChildWorkflowSnapshot')
    expect do
      described_class.new(**common_attributes, child_workflow_id: :shipment, child_workflow: child_workflow(:running))
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'child_workflow_id must match child workflow relationship')
    expect do
      described_class.new(**common_attributes, batch_id: :other_batch, child_workflow: child_workflow(:running))
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'child workflow parent batch must match step batch')
    expect do
      described_class.new(**common_attributes, step_id: :other_step, child_workflow: child_workflow(:running))
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'child workflow parent step must match step id')
    expect do
      described_class.new(**common_attributes, job_id: :other_job, job: job(id: 'other_job'), child_workflow: child_workflow(:running))
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'child workflow parent job must match step job')
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

  it 'validates interaction metadata' do
    expect do
      snapshot(interaction_kind: :webhook, interaction_name: :manager_approved)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'interaction_kind must be :signal or :event')

    expect do
      snapshot(interaction_kind: :signal, interaction_name: :manager_approved, interaction_received_at: '2026-04-24T12:00:00Z')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'interaction_received_at must be a Time')
  end
end
