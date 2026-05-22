# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'workflow_enqueue_request_builder'
require_relative 'workflow_enqueue_insert_builder'

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Registers and enqueues a root durable workflow definition.
        class EnqueueWorkflow < Operation
          include WorkflowOperationSupport

          def call(context:)
            enqueue_request = WorkflowEnqueueRequestBuilder.new(operation: self, context:).build

            WorkflowEnqueueResultBuilder.new(
              now: enqueue_request.now,
              action: :enqueue_many,
              queued_jobs: enqueue_request.queued_jobs,
              inserts: WorkflowEnqueueInsertBuilder.new(
                operation: self,
                enqueue_request:
              ).build
            ).build
          end
        end
      end
    end
  end
end
