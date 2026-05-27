# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Immutable normalized request context for one child-workflow sync sweep.
        SyncChildWorkflowRequest = Struct.new(
          :namespace,
          :context,
          :rows,
          :parent_batch_id,
          :parent_registration,
          :relationships,
          :now,
          keyword_init: true
        )

        # Loads the durable rows and relationship context needed for one child-workflow sync.
        class SyncChildWorkflowRequestBuilder
          def initialize(operation:, context:)
            @operation = operation
            @context = context
          end

          def build
            now = operation.send(:normalized_workflow_now)
            parent_batch_id = Workflow.send(:normalize_batch_identifier, :parent_batch_id, operation.request.fetch(:parent_batch_id))
            namespace = context.namespace
            rows = context.rows.merge(namespace:)
            _batch, parent_registration, = operation.send(:workflow_target, parent_batch_id, rows, now)

            SyncChildWorkflowRequest.new(
              namespace:,
              context:,
              rows:,
              parent_batch_id:,
              parent_registration:,
              relationships: operation.send(:child_relationships_for_parent_batch, rows, parent_batch_id),
              now:
            )
          end

          private

          attr_reader :operation, :context
        end
      end
    end
  end
end
