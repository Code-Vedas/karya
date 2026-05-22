# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Workflow interaction delivery operations persist signals and events.
      module Operations
        require_relative 'workflow_interaction_request_builder'
        require_relative 'workflow_interaction_history_builder'
        require_relative 'workflow_interaction_result_builder'
        require_relative 'workflow_signal_approval_builder'

        # Records durable workflow signals and auto-approval side effects.
        class DeliverWorkflowSignal < Operation
          include WorkflowOperationSupport
          include RecoverySupport
          include ReliabilityPolicySupport

          def call(context:)
            deliver(context, kind: :signal, action: :deliver_workflow_signal)
          end

          private

          def deliver(context, kind:, action:)
            interaction_request = WorkflowInteractionRequestBuilder.new(operation: self, context:, kind:).build
            interaction_row = build_workflow_interaction_row(
              rows: interaction_request.rows,
              namespace: interaction_request.namespace,
              batch_id: interaction_request.batch_id,
              interaction: interaction_request.interaction
            )
            history_row = WorkflowInteractionHistoryBuilder.new(
              operation: self,
              interaction_request:,
              kind:
            ).build
            approval_rows = workflow_signal_approval_rows(kind, interaction_request, history_row)

            WorkflowInteractionResultBuilder.new(
              action:,
              interaction_row:,
              history_row:,
              approval_rows:,
              interaction_request:
            ).build
          end

          def workflow_signal_approval_rows(kind, interaction_request, history_row)
            return WorkflowSignalApprovalRows.new(policy_rows: [], history_rows: []) unless kind == :signal

            WorkflowSignalApprovalBuilder.new(
              operation: self,
              interaction_request: interaction_request.with_history_row(history_row)
            ).build
          end
        end
      end
    end
  end
end
