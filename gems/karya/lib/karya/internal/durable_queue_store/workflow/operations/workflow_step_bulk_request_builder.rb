# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Normalized workflow-step bulk operation inputs.
        WorkflowStepBulkRequest = Struct.new(
          :context,
          :action,
          :now,
          :batch_id,
          :rows,
          :registration,
          :job_ids,
          keyword_init: true
        )

        # Builds the stable row and registration context for workflow-step bulk operations.
        class WorkflowStepBulkRequestBuilder
          def initialize(operation:, context:, action:, now:)
            @operation = operation
            @context = context
            @action = action
            @now = now
          end

          def build
            batch_id = operation.send(:normalized_workflow_batch_id)
            rows = context.rows.merge(namespace: context.namespace)
            _batch, registration, _snapshot = operation.send(:workflow_target, batch_id, rows, now)
            job_ids = operation.send(:workflow_control_job_ids, registration, operation.request.fetch(:step_ids))

            WorkflowStepBulkRequest.new(
              context:,
              action:,
              now:,
              batch_id:,
              rows:,
              registration:,
              job_ids:
            )
          end

          private

          attr_reader :operation, :context, :action, :now
        end
      end
    end
  end
end
