# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Reconstructs the durable workflow snapshot for one workflow batch.
        class WorkflowSnapshot < Operation
          include WorkflowOperationSupport
          include RecoverySupport
          include ReliabilityPolicySupport

          def call(context:)
            now = normalized_workflow_now
            batch_id = normalized_workflow_batch_id
            rows, recovery = WorkflowRuntimeContextBuilder.new(context:, now:, host: self).call
            snapshot = build_workflow_snapshot(rows:, batch_id:, now:, cache: {}, visiting: {})

            OperationResult.new(value: snapshot, mutation_plan: recovery.fetch(:plan), persist: recovery.fetch(:changed))
          end
        end
      end
    end
  end
end
