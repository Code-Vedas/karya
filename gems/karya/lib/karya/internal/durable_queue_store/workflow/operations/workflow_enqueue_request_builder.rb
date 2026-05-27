# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Validates and normalizes the durable root workflow enqueue request.
        WorkflowEnqueueRequest = Struct.new(
          :namespace,
          :definition,
          :now,
          :batch_id,
          :rows,
          :queued_jobs,
          :registration,
          keyword_init: true
        )

        # Builds the normalized request context for a root durable workflow enqueue.
        class WorkflowEnqueueRequestBuilder
          def initialize(operation:, context:)
            @operation = operation
            @context = context
          end

          def build
            definition = workflow_definition
            now = operation.send(:normalized_workflow_now)
            binding = operation.send(:workflow_binding_for, definition)
            batch_id = binding.batch_id
            namespace = context.namespace
            source_rows = context.rows
            rows = source_rows.merge(namespace:)
            raise Workflow::DuplicateBatchError, "batch #{batch_id.inspect} already exists" if operation.send(:workflow_batch_row, source_rows, batch_id)

            queued_jobs = operation.send(:validate_workflow_enqueue_jobs, rows, binding.jobs, now)
            registration = WorkflowRegistrationBuilder.new(
              operation:,
              definition:,
              binding:,
              queued_jobs:
            ).build

            WorkflowEnqueueRequest.new(
              namespace:,
              definition:,
              now:,
              batch_id:,
              rows:,
              queued_jobs:,
              registration:
            )
          end

          private

          attr_reader :operation, :context

          def workflow_definition
            definition = operation.request.fetch(:definition)
            raise Workflow::InvalidExecutionError, 'definition must be a Karya::Workflow::Definition' unless definition.is_a?(Workflow::Definition)

            definition
          end
        end
      end
    end
  end
end
