# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Karya::Internal::DurableQueueStore::WorkflowRuntimeSupport::PolicyRowBuilders do
  include_context 'with durable queue-store operations spec support'

  let(:helper) { helper_class.new(store:, request: {}) }

  it 'builds durable workflow pause, approval, rollback, and child-link policy rows' do
    pause_row = helper.send(:build_workflow_pause_row, namespace:, batch_id: 'batch-1', now:)
    expect(pause_row).to include(policy_kind: 'workflow_pause', scope_kind: 'workflow', scope_value: 'batch-1')

    approval_row = helper.send(:build_workflow_approval_row, namespace:, job_id: 'job-1', state: :rejected, decided_at: now, reason: 'manual')
    approval_payload = Karya::Internal::DurableQueueStore::Operations::PolicyStateRow.new(row: approval_row).payload
    expect(approval_payload).to include('state' => 'rejected', 'reason' => 'manual')

    rollback_row = helper.send(
      :build_workflow_rollback_row,
      namespace:,
      batch_id: 'batch-1',
      rollback_batch_id: 'rollback-1',
      reason: 'manual',
      requested_at: now,
      compensation_job_ids: %w[job-1 job-2]
    )
    expect(Karya::Internal::DurableQueueStore::Operations::PolicyStateRow.new(row: rollback_row).payload).to include(
      'rollback_batch_id' => 'rollback-1',
      'compensation_job_ids' => %w[job-1 job-2]
    )

    definition = Karya::Workflow.define(:child) { step :capture, handler: :capture }
    relationship_rows = helper.send(
      :build_workflow_child_relationship_rows,
      namespace:,
      parent: {
        parent_workflow_id: 'approval',
        parent_workflow_family: 'approval',
        parent_workflow_version: 'v1',
        parent_batch_id: 'parent-batch',
        parent_job_id: 'job-parent'
      },
      parent_step_id: 'approve',
      definition:,
      child_batch_id: 'child-batch',
      now:
    )
    expect(relationship_rows.map { |row| row.fetch(:scope_kind) }).to eq(%w[parent_step parent_job child_batch])
  end

  it 'validates workflow interaction support against the durable registration' do
    rows = workflow_enqueue_rows(
      definition: Karya::Workflow.define(:approval) do
        step :approve, handler: :approve, wait_for_approval: :approve_signal
      end,
      jobs_by_step_id: { approve: job(id: 'job-approve', state: :submission, handler: :approve) },
      batch_id: :helper_batch
    )
    registration = helper.send(:registration_for_batch, rows, 'helper_batch')

    expect do
      helper.send(:validate_workflow_interaction_support!, registration, :signal, 'approve_signal', 'helper_batch')
    end.not_to raise_error

    expect do
      helper.send(:validate_workflow_interaction_support!, registration, :event, 'missing', 'helper_batch')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /does not support event "missing"/)
  end
end
