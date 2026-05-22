# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'dead_letter_workflow_step_transition_builder'

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Moves selected workflow step jobs into durable dead-letter state.
        class DeadLetterWorkflowSteps < WorkflowStepBulkOperation
          def call(context:)
            now = normalized_workflow_now
            reason = Karya::Internal::DeadLetterReason.normalize(request.fetch(:reason), error_class: Workflow::InvalidExecutionError)
            report, plan, persist = workflow_bulk_report(context, :dead_letter_workflow_steps, now) do |mutation|
              DeadLetterWorkflowStepTransitionBuilder.new(mutation:, now:, reason:).build
            end
            OperationResult.new(value: report, mutation_plan: plan, persist:)
          end
        end
      end
    end
  end
end
