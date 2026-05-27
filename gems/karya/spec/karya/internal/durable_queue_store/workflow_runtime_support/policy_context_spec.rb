# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Karya::Internal::DurableQueueStore::WorkflowRuntimeSupport::PolicyContext do
  include_context 'with durable queue-store operations spec support'

  let(:rows) { empty_rows }

  it 'reads workflow pause state and approval decisions from durable policy rows' do
    paused_rows = rows.merge(
      policy_state: [
        policy_row(
          policy_kind: 'workflow_pause',
          scope_kind: 'workflow',
          scope_value: 'batch-1',
          state_payload: Karya::Internal::DurableQueueStore::PolicyStateRecord.stringify_payload(requested_at: now)
        ),
        policy_row(
          policy_kind: 'workflow_approval_decision',
          scope_kind: 'job',
          scope_value: 'job-approve',
          state_payload: Karya::Internal::DurableQueueStore::PolicyStateRecord.stringify_payload(
            state: :rejected,
            decided_at: now,
            reason: 'manual'
          )
        )
      ]
    )
    context = described_class.new(rows: paused_rows)

    expect(context.pause_requested_at('batch-1')).to eq(now)
    expect(context.pause_requested_at('missing')).to be_nil
    expect(context.approval_decision_for('missing')).to be_nil
    expect(context.approval_decision_for('job-approve').to_snapshot_decision).to include(reason: 'manual')
  end

  it 'builds durable approval-decision and interaction snapshots' do
    definition = Karya::Workflow.define(:approval) do
      step :approve, handler: :approve, wait_for_approval: :approve_signal
      step :signal_step, handler: :signal_step, wait_for_signal: :ready_signal, depends_on: :approve
      step :event_step, handler: :event_step, wait_for_event: :ready_event, depends_on: :signal_step
    end
    workflow_rows = workflow_enqueue_rows(
      definition:,
      jobs_by_step_id: {
        approve: job(id: 'job-approve', state: :submission, handler: :approve),
        signal_step: job(id: 'job-signal', state: :submission, handler: :signal_step),
        event_step: job(id: 'job-event', state: :submission, handler: :event_step)
      },
      batch_id: :helper_batch
    )
    rows_with_policy = workflow_rows.merge(
      policy_state: [
        policy_row(
          policy_kind: 'workflow_approval_decision',
          scope_kind: 'job',
          scope_value: 'job-approve',
          state_payload: Karya::Internal::DurableQueueStore::PolicyStateRecord.stringify_payload(
            state: :approved,
            decided_at: now
          )
        )
      ],
      workflow_interactions: [
        Karya::Internal::DurableQueueStore::WorkflowInteractionRecord.new(
          namespace:,
          batch_id: 'helper_batch',
          sequence: 1,
          interaction: Karya::Workflow::InteractionSnapshot.new(kind: :signal, name: 'ready_signal', payload: {}, received_at: now)
        ).to_h,
        Karya::Internal::DurableQueueStore::WorkflowInteractionRecord.new(
          namespace:,
          batch_id: 'helper_batch',
          sequence: 2,
          interaction: Karya::Workflow::InteractionSnapshot.new(kind: :signal, name: 'approve_signal', payload: {}, received_at: now)
        ).to_h
      ]
    )
    registration = helper_class.new(store:, request: {}).send(:registration_for_batch, rows_with_policy, 'helper_batch')
    context = described_class.new(rows: rows_with_policy)

    expect(context.approval_decisions(registration)).to eq(
      'job-approve' => { state: :approved, decided_at: now }
    )
    expect(context.interaction_delivered?(batch_id: 'helper_batch', kind: :signal, name: 'ready_signal')).to be(true)
    expect(context.interaction_delivered?(batch_id: 'helper_batch', kind: :signal, name: 'missing')).to be(false)
    expect(context.interaction_received_at_by_job_id('helper_batch', registration)).to include('job-signal' => now)
  end

  it 'builds durable rollback snapshots from workflow policy rows' do
    rows_with_rollback = rows.merge(
      policy_state: [
        policy_row(
          policy_kind: 'workflow_rollback',
          scope_kind: 'workflow',
          scope_value: 'batch-1',
          state_payload: Karya::Internal::DurableQueueStore::PolicyStateRecord.stringify_payload(
            batch_id: 'batch-1',
            rollback_batch_id: 'rollback-1',
            reason: 'manual',
            requested_at: now,
            compensation_job_ids: %w[job-1 job-2]
          )
        )
      ]
    )
    context = described_class.new(rows: rows_with_rollback)

    expect(context.rollback_snapshot('missing')).to be_nil
    expect(context.rollback_snapshot('batch-1')).to have_attributes(
      workflow_batch_id: 'batch-1',
      rollback_batch_id: 'rollback-1',
      reason: 'manual',
      requested_at: now,
      compensation_job_ids: %w[job-1 job-2]
    )
  end
end
