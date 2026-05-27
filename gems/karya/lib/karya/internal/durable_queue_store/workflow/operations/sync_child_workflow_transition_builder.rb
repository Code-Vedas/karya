# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Immutable transition outcome for syncing one parent job from a child workflow state.
        SyncChildTransition = Struct.new(
          :parent_job,
          :mutated_job,
          :action,
          :details,
          :child_batch_id,
          keyword_init: true
        )

        # Builds the failed-child transition for a parent workflow job.
        class FailedChildWorkflowTransition
          def initialize(parent_job:, relationship:, now:)
            @parent_job = parent_job
            @relationship = relationship
            @now = now
          end

          def build
            return unless parent_job.can_transition_to?(:dead_letter)

            {
              mutated_job: parent_job.transition_to(
                :dead_letter,
                updated_at: now,
                next_retry_at: nil,
                failure_classification: parent_job.failure_classification,
                dead_letter_reason: "child workflow #{relationship.child_batch_id} failed",
                dead_lettered_at: now,
                dead_letter_source_state: parent_job.state
              ),
              action: :child_workflow_sync_failed,
              details: { 'child_state' => 'failed' }
            }.freeze
          end

          private

          attr_reader :parent_job, :relationship, :now
        end

        # Builds the cancelled-child transition for a parent workflow job.
        class CancelledChildWorkflowTransition
          def initialize(parent_job:, now:)
            @parent_job = parent_job
            @now = now
          end

          def build
            return unless parent_job.can_transition_to?(:cancelled)

            {
              mutated_job: parent_job.transition_to(:cancelled, updated_at: now, next_retry_at: nil, failure_classification: nil),
              action: :child_workflow_sync_cancelled,
              details: { 'child_state' => 'cancelled' }
            }.freeze
          end

          private

          attr_reader :parent_job, :now
        end

        # Builds the durable parent-job transition implied by one child workflow state.
        class SyncChildWorkflowTransitionBuilder
          def initialize(operation:, rows:, job_id:, now:)
            @operation = operation
            @rows = rows
            @job_id = job_id
            @now = now
          end

          def build
            relationship = operation.send(:child_relationship_for_parent_job, rows, job_id)
            child_batch_id = relationship.child_batch_id
            child_state = operation.send(:workflow_state_for_batch, rows, child_batch_id, now, cache: {}, visiting: {})
            parent_job = Operations::JobRow.new(row: Operations::RowIndex.new(rows:).jobs_by_id.fetch(job_id)).to_job
            mutation = transition_for(parent_job, child_state, relationship)

            return SyncChildTransition.new(parent_job:, child_batch_id:) unless mutation

            SyncChildTransition.new(
              parent_job:,
              mutated_job: mutation.fetch(:mutated_job),
              action: mutation.fetch(:action),
              details: mutation.fetch(:details),
              child_batch_id:
            )
          end

          private

          attr_reader :operation, :rows, :job_id, :now

          def transition_for(parent_job, child_state, relationship)
            case child_state
            when :failed
              FailedChildWorkflowTransition.new(parent_job:, relationship:, now:).build
            when :cancelled
              CancelledChildWorkflowTransition.new(parent_job:, now:).build
            end
          end
        end
      end
    end
  end
end
