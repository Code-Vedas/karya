# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds the durable resume-workflow mutation plan from a normalized control request.
        class ResumeWorkflowMutationBuilder
          def initialize(operation:, control_request:)
            @operation = operation
            @control_request = control_request
          end

          def build
            MutationPlan.new(
              deletes: { policy_state: pause_row ? [pause_row] : [] },
              inserts: { workflow_history: [history_row] }
            )
          end

          private

          attr_reader :operation, :control_request

          def batch_id
            control_request.batch_id
          end

          def pause_row
            @pause_row ||= control_request.rows.fetch(:policy_state).find do |row|
              row.fetch(:policy_kind) == 'workflow_pause' &&
                row.fetch(:scope_kind) == 'workflow' &&
                row.fetch(:scope_value) == batch_id
            end
          end

          def history_row
            operation.send(
              :workflow_control_row,
              rows: control_request.rows,
              namespace: control_request.namespace,
              batch_id:,
              entry: WorkflowControlEntryBuilder.new(
                registration: control_request.registration,
                batch_id:,
                occurred_at: control_request.now,
                entry: { kind: :control, action: :resumed }
              ).build
            )
          end
        end
      end
    end
  end
end
