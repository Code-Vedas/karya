# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'rejection_checkpoint_request_builder'
require_relative 'rejection_checkpoint_result_builder'

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Rejects workflow checkpoint steps and applies the resulting job transitions.
        class RejectWorkflowCheckpoints < Operation
          include WorkflowOperationSupport

          def call(context:)
            rejection_request = RejectionCheckpointRequestBuilder.new(operation: self, context:).build
            report, plan, changed = RejectionCheckpointResultBuilder.new(
              operation: self,
              request: rejection_request
            ).build

            OperationResult.new(value: report, mutation_plan: plan, persist: changed)
          end
        end
      end
    end
  end
end
