# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'workflow_enqueue_support'
require_relative 'workflow_runtime_context_support'
require_relative 'workflow_runtime_context_builder'
require_relative 'workflow_control_entry_builder'

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Shared workflow-specific row-native helpers.
        module WorkflowOperationSupport
          include SharedSupport
          include RowSupport
          include BulkMutationSupport
          include WorkflowEnqueueSupport
          include WorkflowRuntimeContextSupport

          private

          def normalized_workflow_now
            normalize_time(:now, request.fetch(:now), error_class: Workflow::InvalidExecutionError)
          end

          def normalized_workflow_batch_id(field_name = :batch_id)
            Workflow.send(:normalize_batch_identifier, field_name, request.fetch(field_name))
          end
        end
      end
    end
  end
end
