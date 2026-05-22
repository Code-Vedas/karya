# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'child_workflow_request_builder'
require_relative 'child_workflow_insert_builder'

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Registers and enqueues a durable child workflow for a parent step.
        class EnqueueChildWorkflow < Operation
          include WorkflowOperationSupport

          def call(context:)
            child_request = ChildWorkflowRequestBuilder.new(operation: self, context:).build
            inserts = ChildWorkflowInsertBuilder.new(
              operation: self,
              namespace: context.namespace,
              child_request:
            ).build

            WorkflowEnqueueResultBuilder.new(
              now: child_request.now,
              action: :enqueue_child_workflow,
              queued_jobs: child_request.queued_jobs,
              inserts:
            ).build
          end
        end
      end
    end
  end
end
