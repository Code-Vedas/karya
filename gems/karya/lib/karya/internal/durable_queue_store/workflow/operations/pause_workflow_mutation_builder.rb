# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds the durable pause-workflow mutation plan from a normalized control request.
        class PauseWorkflowMutationBuilder
          def initialize(operation:, control_request:, recovery_plan:)
            @operation = operation
            @control_request = control_request
            @recovery_plan = recovery_plan
          end

          def build
            MutationPlan.new(
              inserts: {
                policy_state: [operation.send(:build_workflow_pause_row, namespace:, batch_id:, now:)],
                workflow_history: [history_row]
              },
              updates: recovery_plan.updates,
              deletes: recovery_plan.deletes
            )
          end

          private

          attr_reader :operation, :control_request, :recovery_plan

          def namespace
            control_request.namespace
          end

          def batch_id
            control_request.batch_id
          end

          def now
            control_request.now
          end

          def history_row
            operation.send(
              :workflow_control_row,
              rows: control_request.rows,
              namespace:,
              batch_id:,
              entry: WorkflowControlEntryBuilder.new(
                registration: control_request.registration,
                batch_id:,
                occurred_at: now,
                entry: { kind: :control, action: :pause_requested }
              ).build
            )
          end
        end
      end
    end
  end
end
