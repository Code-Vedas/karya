# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::WorkflowRuntimeSupport do
  include_context 'with durable queue-store operations spec support'

  it 'covers workflow runtime delegation paths' do
    helper = workflow_runtime_helper_class.new(store:, request: {})
    definition = Karya::Workflow.define(:approval) do
      step :approve, handler: :approve, wait_for_approval: :approve_signal
    end
    rows = workflow_enqueue_rows(
      definition:,
      jobs_by_step_id: { approve: job(id: 'job-approve', state: :submission, handler: :approve) },
      batch_id: :helper_batch
    )
    history_entry = Karya::Workflow::HistoryEntry.new(
      kind: :workflow,
      action: :enqueued,
      occurred_at: now,
      workflow_id: 'approval',
      workflow_family: 'approval',
      workflow_version: 'v1',
      batch_id: 'helper_batch',
      details: {}
    )
    history_rows = rows.merge(
      workflow_history: [
        helper.send(:build_workflow_history_row, rows:, namespace:, batch_id: 'helper_batch', entry: history_entry)
      ],
      policy_state: [
        policy_row(
          policy_kind: 'workflow_pause',
          scope_kind: 'workflow',
          scope_value: 'helper_batch',
          state_payload: Karya::Internal::DurableQueueStore::PolicyStateRecord.stringify_payload(requested_at: now)
        ),
        policy_row(
          policy_kind: 'workflow_child_relationship',
          scope_kind: 'child_batch',
          scope_value: 'child_batch',
          state_payload: Karya::Internal::DurableQueueStore::PolicyStateRecord.stringify_payload(
            parent_workflow_id: 'approval',
            parent_workflow_family: 'approval',
            parent_workflow_version: 'v1',
            parent_batch_id: 'helper_batch',
            parent_step_id: 'approve',
            parent_job_id: 'job-approve',
            child_workflow_id: 'child',
            child_workflow_family: 'child',
            child_workflow_version: 'v1',
            child_batch_id: 'child_batch'
          )
        )
      ]
    )

    expect(helper.send(:workflow_history_entries, history_rows, 'helper_batch').map { |entry| entry.action.to_s }).to eq(['enqueued'])
    expect(helper.send(:workflow_paused?, history_rows, 'helper_batch')).to be(true)
    expect(helper.send(:child_relationship_for_child_batch, history_rows, 'child_batch').parent_batch_id).to eq('helper_batch')
    registration = helper.send(:registration_for_batch, rows, 'helper_batch')
    expect(
      helper.send(:workflow_child_satisfied?, rows.merge(workflow_steps: []), registration, job(id: 'job-approve', state: :queued, handler: :approve), now)
    ).to be(true)

    updated_rows = helper.send(
      :update_rows_with_workflow_job,
      history_rows.merge(namespace:),
      'job-approve',
      job(id: 'job-approve', state: :failed, handler: :approve)
    )
    expect(Karya::Internal::DurableQueueStore::Operations::JobRow.new(row: updated_rows.fetch(:jobs).first).to_job.state).to eq(:failed)
    expect(
      helper.send(
        :workflow_history_rows_for_job,
        rows.merge(workflow_steps: []),
        namespace:,
        replacement_job: job(id: 'job-approve', state: :failed, handler: :approve),
        from_state: :queued
      )
    ).to eq([])
  end
end
