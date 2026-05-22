# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds the durable running-state mutation for one reserved job.
        class StartExecutionResultBuilder
          def initialize(operation:, context:, lease:)
            @operation = operation
            @context = context
            @lease = lease
          end

          def build
            OperationResult.new(
              value: running_job,
              mutation_plan: MutationPlan.new(
                updates: {
                  jobs: [JobRecord.new(namespace: context.namespace, job: running_job).to_h],
                  workflow_steps: workflow_updates.fetch(:workflow_steps),
                  workflow_batches: workflow_updates.fetch(:workflow_batches),
                  reservations: [running_reservation_row]
                },
                inserts: { workflow_history: workflow_effects.workflow_history_rows }
              ),
              persist: true
            )
          end

          private

          attr_reader :operation, :context, :lease

          def reserved_job
            lease.job
          end

          def running_job
            @running_job ||= reserved_job.transition_to(:running, updated_at: lease.now, attempt: reserved_job.attempt + 1)
          end

          def running_reservation_row
            lease.reservation_row.merge(phase: 'running')
          end

          def workflow_effects
            @workflow_effects ||= WorkflowJobEffects.new(operation:, context:, job: running_job)
          end

          def workflow_updates
            @workflow_updates ||= workflow_effects.workflow_updates
          end
        end
      end
    end
  end
end
