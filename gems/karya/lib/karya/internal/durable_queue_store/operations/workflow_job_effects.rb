# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Loads durable workflow row changes for one replacement job.
        class WorkflowJobEffects
          def initialize(operation:, context:, job:)
            @operation = operation
            @context = context
            @job = job
          end

          def workflow_updates
            operation.send(:workflow_row_updates_for_job, context, workflow_rows, job)
          end

          def workflow_history_rows
            operation.send(
              :workflow_history_rows_for_job,
              workflow_rows,
              namespace: context.namespace,
              replacement_job: job
            )
          end

          private

          attr_reader :operation, :context, :job

          def workflow_rows
            @workflow_rows ||= context.rows.merge(namespace: context.namespace)
          end
        end
      end
    end
  end
end
