# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Rebuilds workflow runtime rows, targets, and control history entries.
        module WorkflowRuntimeContextSupport
          private

          def build_workflow_control_history_row(rows:, namespace:, batch_id:, entry:)
            build_workflow_history_row(rows:, namespace:, batch_id:, entry:)
          end

          def workflow_target(batch_id, rows, now)
            batch = workflow_batch_from_rows(rows, batch_id)
            registration = registration_for_batch(rows, batch_id)
            snapshot = build_workflow_snapshot(rows:, batch_id:, now:, cache: {}, visiting: {})
            [batch, registration, snapshot]
          end

          def terminal_workflow_control!(snapshot, batch_id, action)
            return unless WorkflowRuntimeSupport::WORKFLOW_INTERACTION_TERMINAL_STATES.include?(snapshot.state)

            raise Workflow::InvalidExecutionError, "workflow batch #{batch_id.inspect} is terminal and cannot #{action}"
          end

          def workflow_control_row(rows:, namespace:, batch_id:, entry:)
            build_workflow_control_history_row(rows:, namespace:, batch_id:, entry:)
          end
        end
      end
    end
  end
end
