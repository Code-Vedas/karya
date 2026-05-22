# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Workflow::ChildWorkflowSnapshot do
  let(:snapshot) do
    described_class.new(
      parent_workflow_id: ' parent ',
      parent_batch_id: ' parent-batch ',
      parent_step_id: ' child-step ',
      parent_job_id: ' parent-job ',
      child_workflow_id: ' child ',
      child_batch_id: ' child-batch ',
      child_state: :running
    )
  end

  it 'normalizes ids and freezes the snapshot' do
    expect(snapshot).to have_attributes(
      parent_workflow_id: 'parent',
      parent_workflow_family: 'parent',
      parent_workflow_version: 'v1',
      parent_batch_id: 'parent-batch',
      parent_step_id: 'child-step',
      parent_job_id: 'parent-job',
      child_workflow_id: 'child',
      child_workflow_family: 'child',
      child_workflow_version: 'v1',
      child_batch_id: 'child-batch',
      child_state: :running
    )
    expect(snapshot).to be_frozen
  end

  it 'accepts explicit parent and child version identity' do
    versioned = described_class.new(
      parent_workflow_id: :invoice_closeout_v1,
      parent_workflow_family: :invoice_closeout,
      parent_workflow_version: :v1,
      parent_batch_id: :parent_batch,
      parent_step_id: :child_step,
      parent_job_id: :parent_job,
      child_workflow_id: :payment_v2,
      child_workflow_family: :payment,
      child_workflow_version: :v2,
      child_batch_id: :child_batch,
      child_state: :running
    )

    expect(versioned).to have_attributes(
      parent_workflow_family: 'invoice_closeout',
      parent_workflow_version: 'v1',
      child_workflow_family: 'payment',
      child_workflow_version: 'v2'
    )
  end

  it 'rejects invalid workflow states' do
    expect do
      described_class.new(
        parent_workflow_id: :parent,
        parent_batch_id: :parent_batch,
        parent_step_id: :child_step,
        parent_job_id: :parent_job,
        child_workflow_id: :child,
        child_batch_id: :child_batch,
        child_state: :unknown
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'child_state must be a workflow state')
  end

  it 'accepts paused and awaiting_approval child workflow states' do
    paused = described_class.new(
      parent_workflow_id: :parent,
      parent_batch_id: :parent_batch,
      parent_step_id: :child_step,
      parent_job_id: :parent_job,
      child_workflow_id: :child,
      child_batch_id: :child_batch,
      child_state: :paused
    )
    awaiting_approval = described_class.new(
      parent_workflow_id: :parent,
      parent_batch_id: :parent_batch,
      parent_step_id: :child_step,
      parent_job_id: :parent_job,
      child_workflow_id: :child,
      child_batch_id: :child_batch,
      child_state: :awaiting_approval
    )

    expect(paused.child_state).to eq(:paused)
    expect(awaiting_approval.child_state).to eq(:awaiting_approval)
  end

  it 'rejects unknown attributes' do
    expect do
      described_class.new(
        parent_workflow_id: :parent,
        parent_batch_id: :parent_batch,
        parent_step_id: :child_step,
        parent_job_id: :parent_job,
        child_workflow_id: :child,
        child_batch_id: :child_batch,
        child_state: :running,
        unexpected: true
      )
    end.to raise_error(ArgumentError, 'unknown keyword: :unexpected')
  end
end
