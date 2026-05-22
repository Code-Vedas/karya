# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Workflow interaction delivery operations build durable rows from normalized request state.

        # Immutable request context for one durable workflow interaction delivery.
        WorkflowInteractionRequest = Struct.new(
          :namespace,
          :now,
          :batch_id,
          :rows,
          :registration,
          :snapshot,
          :interaction,
          keyword_init: true
        ) do
          def name
            interaction.name
          end

          def with_history_row(history_row)
            self.class.new(
              namespace:,
              now:,
              batch_id:,
              rows: rows.merge(workflow_history: rows.fetch(:workflow_history) + [history_row]),
              registration:,
              snapshot:,
              interaction:
            )
          end
        end

        # Rebuilds durable workflow interaction inputs before a signal/event mutation plan.
        class WorkflowInteractionRequestBuilder
          def initialize(operation:, context:, kind:)
            @operation = operation
            @context = context
            @kind = kind
          end

          def build
            now = operation.send(:normalized_workflow_now)
            batch_id = operation.send(:normalized_workflow_batch_id)
            rows = runtime_rows(now)
            _batch, registration, snapshot = operation.send(:workflow_target, batch_id, rows, now)
            operation.send(:terminal_workflow_control!, snapshot, batch_id, 'receive interactions')
            name = normalized_name
            operation.send(:validate_workflow_interaction_support!, registration, kind, name, batch_id)

            WorkflowInteractionRequest.new(
              namespace: context.namespace,
              now:,
              batch_id:,
              rows:,
              registration:,
              snapshot:,
              interaction: Workflow::InteractionSnapshot.new(
                kind:,
                name:,
                payload: operation.request.fetch(:payload),
                received_at: now
              )
            )
          end

          private

          attr_reader :operation, :context, :kind

          def runtime_rows(now)
            WorkflowRuntimeContextBuilder.new(context:, now:, host: operation).call.first
          end

          def normalized_name
            field_name = kind == :signal ? :signal : :event
            Workflow.send(:normalize_execution_identifier, field_name, operation.request.fetch(field_name))
          end
        end
      end
    end
  end
end
