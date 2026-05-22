# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Builds child workflow snapshots from a durable relationship.
        class ChildWorkflowSnapshotBuilder
          def initialize(snapshot_context:, relationship:)
            @snapshot_context = snapshot_context
            @relationship = relationship
          end

          def build
            Workflow::ChildWorkflowSnapshot.new(
              parent_workflow_id: relationship.parent_workflow_id,
              parent_workflow_family: relationship.parent_workflow_family,
              parent_workflow_version: relationship.parent_workflow_version,
              parent_batch_id: relationship.parent_batch_id,
              parent_step_id: relationship.parent_step_id,
              parent_job_id: relationship.parent_job_id,
              child_workflow_id: relationship.child_workflow_id,
              child_workflow_family: relationship.child_workflow_family,
              child_workflow_version: relationship.child_workflow_version,
              child_batch_id:,
              child_state:
            )
          end

          private

          attr_reader :snapshot_context, :relationship

          def host = snapshot_context.host
          def rows = snapshot_context.rows
          def now = snapshot_context.now
          def cache = snapshot_context.cache
          def visiting = snapshot_context.visiting

          def child_batch_id
            @child_batch_id ||= relationship.child_batch_id
          end

          def child_state
            return host.send(:workflow_batch_row, rows, child_batch_id).fetch(:state).to_sym if visiting.key?(child_batch_id)

            host.send(:workflow_state_for_batch, rows, child_batch_id, now, cache:, visiting:)
          end
        end
      end
    end
  end
end
