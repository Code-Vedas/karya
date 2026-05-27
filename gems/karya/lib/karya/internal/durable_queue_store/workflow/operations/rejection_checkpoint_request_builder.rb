# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Normalized request context for rejecting workflow checkpoints.
        RejectionCheckpointRequest = Struct.new(
          :context,
          :batch_id,
          :rows,
          :registration,
          :snapshot,
          :job_ids,
          :now,
          :reason,
          keyword_init: true
        )

        # Builds the workflow rows and normalized inputs for rejection operations.
        class RejectionCheckpointRequestBuilder
          def initialize(operation:, context:)
            @operation = operation
            @context = context
          end

          def build
            now = operation.send(:normalized_workflow_now)
            batch_id = operation.send(:normalized_workflow_batch_id)
            rows = context.rows.merge(namespace: context.namespace)
            _batch, registration, snapshot = operation.send(:workflow_target, batch_id, rows, now)
            request = operation.request
            job_ids = operation.send(:workflow_control_job_ids, registration, request.fetch(:step_ids))
            reason = Karya::Internal::DeadLetterReason.normalize(
              request.fetch(:reason),
              error_class: Workflow::InvalidExecutionError
            )

            RejectionCheckpointRequest.new(
              context:,
              batch_id:,
              rows:,
              registration:,
              snapshot:,
              job_ids:,
              now:,
              reason:
            )
          end

          private

          attr_reader :operation, :context
        end
      end
    end
  end
end
