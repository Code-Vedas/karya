# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds the durable queue-state mutation for releasing one lease.
        class ReleaseResultBuilder
          def initialize(operation:, context:, lease:)
            @operation = operation
            @context = context
            @lease = lease
          end

          def build
            OperationResult.new(
              value: queued_job,
              mutation_plan: MutationPlan.new(
                updates: {
                  jobs: [JobRecord.new(namespace: context.namespace, job: queued_job).to_h],
                  workflow_steps: workflow_updates.fetch(:workflow_steps),
                  workflow_batches: workflow_updates.fetch(:workflow_batches)
                },
                inserts: { queue_entries: [queue_entry_row] },
                deletes: { reservations: [lease.reservation_row] }
              ),
              persist: true
            )
          end

          private

          attr_reader :operation, :context, :lease

          def queued_job
            @queued_job ||= lease.job.transition_to(:queued, updated_at: lease.now, failure_classification: nil)
          end

          def workflow_updates
            @workflow_updates ||= WorkflowJobEffects.new(operation:, context:, job: queued_job).workflow_updates
          end

          def queue_entry_row
            QueueEntryRecord.new(
              namespace: context.namespace,
              job: queued_job,
              insertion_sequence: QueueEntrySequence.new(
                queue_entries: context.rows.fetch(:queue_entries),
                queue: queued_job.queue
              ).next_value
            ).to_h
          end
        end
      end
    end
  end
end
