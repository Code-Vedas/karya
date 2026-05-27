# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'rollback_request_builder'
require_relative 'rollback_insert_builder'

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Enqueues compensation work and durable rollback metadata for a workflow batch.
        class RollbackWorkflow < Operation
          include WorkflowOperationSupport

          def call(context:)
            rollback_request = RollbackRequestBuilder.new(operation: self, context:).build
            inserts = RollbackInsertBuilder.new(
              operation: self,
              namespace: context.namespace,
              rollback_request:
            ).build

            WorkflowEnqueueResultBuilder.new(
              now: rollback_request.now,
              action: :rollback_workflow,
              queued_jobs: rollback_request.queued_jobs,
              inserts:
            ).build
          end
        end
      end
    end
  end
end
