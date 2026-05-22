# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'retry_dead_letter_workflow_step_transition_builder'

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Retries dead-lettered workflow step jobs through retry-pending state.
        class RetryDeadLetterWorkflowSteps < WorkflowStepBulkOperation
          def call(context:)
            now = normalized_workflow_now
            next_retry_at = normalize_time(:next_retry_at, request.fetch(:next_retry_at), error_class: Workflow::InvalidExecutionError)
            report, plan, persist = workflow_bulk_report(context, :retry_dead_letter_workflow_steps, now) do |mutation|
              RetryDeadLetterWorkflowStepTransitionBuilder.new(
                operation: self,
                mutation:,
                now:,
                next_retry_at:
              ).build
            end
            OperationResult.new(value: report, mutation_plan: plan, persist:)
          end
        end
      end
    end
  end
end
