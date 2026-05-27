# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'sync_child_workflow_request_builder'
require_relative 'sync_child_workflow_result_builder'
require_relative 'sync_child_workflow_transition_builder'

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Synchronizes parent workflow jobs from the terminal state of child workflows.
        class SyncChildWorkflows < Operation
          include WorkflowOperationSupport

          def call(context:)
            request = SyncChildWorkflowRequestBuilder.new(operation: self, context:).build
            report, plan, changed = SyncChildWorkflowResultBuilder.new(
              operation: self,
              request:
            ).build

            OperationResult.new(value: report, mutation_plan: plan, persist: changed)
          end
        end
      end
    end
  end
end
