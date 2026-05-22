# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'retry_workflow_step_transition_builder'

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Retries failed or retry-pending workflow step jobs.
        class RetryWorkflowSteps < WorkflowStepBulkOperation
          def call(context:)
            now = normalized_workflow_now
            report, plan, persist = workflow_bulk_report(context, :retry_workflow_steps, now) do |mutation|
              RetryWorkflowStepTransitionBuilder.new(operation: self, mutation:, now:).build
            end
            OperationResult.new(value: report, mutation_plan: plan, persist:)
          end
        end
      end
    end
  end
end
