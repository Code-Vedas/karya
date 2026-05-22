# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::WorkflowRuntimeSupport::WorkflowChildRelationships do
  include_context 'with durable queue-store operations spec support'

  it 'returns no policy rows for unsupported relationship scopes' do
    helper = workflow_runtime_helper_class.new(store:, request: {})
    relationship_row = policy_row(
      policy_kind: 'workflow_child_relationship',
      scope_kind: 'parent_step',
      scope_value: 'helper_batch:step-a',
      state_payload: {
        parent_workflow_id: 'workflow-parent',
        parent_workflow_family: 'billing',
        parent_workflow_version: 'v1',
        parent_batch_id: 'helper_batch',
        parent_step_id: 'step-a',
        parent_job_id: 'job-a',
        child_workflow_id: 'workflow-child',
        child_workflow_family: 'billing-child',
        child_workflow_version: 'v1',
        child_batch_id: 'child-batch'
      }
    )
    relationships = described_class.new(host: helper, rows: { policy_state: [relationship_row] })

    expect(relationships.send(:relationship_policy_rows, 'child_batch', 'helper_batch')).to eq([])
  end
end
