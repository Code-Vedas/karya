# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Immutable durable workflow control request context for pause and resume operations.
        WorkflowControlRequest = Struct.new(
          :namespace,
          :now,
          :batch_id,
          :rows,
          :registration,
          :snapshot,
          keyword_init: true
        )

        # Rebuilds durable workflow rows and target state for control-plane workflow operations.
        class WorkflowControlRequestBuilder
          def initialize(operation:, context:, control_verb:, recover: true)
            @operation = operation
            @context = context
            @control_verb = control_verb
            @recover = recover
          end

          def build
            now = operation.send(:normalized_workflow_now)
            batch_id = operation.send(:normalized_workflow_batch_id)
            rows = WorkflowRuntimeContextBuilder.new(context:, now:, host: operation, recover:).call.first
            _batch, registration, snapshot = operation.send(:workflow_target, batch_id, rows, now)
            operation.send(:terminal_workflow_control!, snapshot, batch_id, control_verb)

            WorkflowControlRequest.new(
              namespace: context.namespace,
              now:,
              batch_id:,
              rows:,
              registration:,
              snapshot:
            )
          end

          private

          attr_reader :operation, :context, :control_verb, :recover
        end
      end
    end
  end
end
