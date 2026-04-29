# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Owner-local workflow history inspection and journal helpers.
        module WorkflowHistorySupport
          def workflow_history(batch_id:, now:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)
            normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)

            @mutex.synchronize do
              recover_in_flight_locked(normalized_now)
              batch = fetch_batch(normalized_batch_id)
              registration = fetch_workflow_registration(batch.id)
              WorkflowHistoryBuilder.new(batch:, registration:, now: normalized_now, state:).to_snapshot
            end
          end

          private

          def record_workflow_registration_history(batch_id:, registration:, occurred_at:)
            step_job_ids = registration.step_job_ids
            state.register_workflow_history_entry(
              batch_id:,
              kind: :workflow,
              action: :workflow_registered,
              occurred_at:,
              details: { 'step_count' => step_job_ids.length }
            )
            step_job_ids.each do |step_id, job_id|
              state.register_workflow_history_entry(
                batch_id:,
                kind: :step,
                action: :queued,
                occurred_at:,
                step_id:,
                job_id:,
                details: { 'from_state' => 'submission' }
              )
            end
          end

          def record_workflow_step_control(batch_id:, registration:, action:, job_id:, occurred_at:)
            state.register_workflow_history_entry(
              batch_id:,
              kind: :control,
              action:,
              occurred_at:,
              step_id: registration.step_job_ids.key(job_id),
              job_id:
            )
          end

          def record_workflow_rollback_history(batch_id:, rollback_batch_id:, queued_job_ids:, reason:, occurred_at:)
            rollback_boundary_action = rollback_batch_id ? :rollback_batch_created : :rollback_noop_boundary
            state.register_workflow_history_entry(
              batch_id:,
              kind: :rollback,
              action: :rollback_requested,
              occurred_at:,
              child_batch_id: rollback_batch_id,
              details: {
                'reason' => reason,
                'compensation_job_ids' => queued_job_ids,
                'rollback_batch_created' => (rollback_boundary_action == :rollback_batch_created)
              }
            )
            state.register_workflow_history_entry(
              batch_id:,
              kind: :rollback,
              action: rollback_boundary_action,
              occurred_at:,
              child_batch_id: rollback_batch_id,
              details: { 'compensation_job_ids' => queued_job_ids }
            )
          end

          # Builds workflow history snapshots from stored workflow metadata.
          class WorkflowHistoryBuilder
            def initialize(batch:, registration:, now:, state:)
              @batch = batch
              @registration = registration
              @now = now
              @state = state
            end

            def to_snapshot
              workflow_batch_id = batch.id
              Workflow::HistorySnapshot.new(
                workflow_id: registration.workflow_id,
                workflow_family: registration.workflow_family,
                workflow_version: registration.workflow_version,
                batch_id: workflow_batch_id,
                captured_at: now,
                entries: state.workflow_history_for(workflow_batch_id)
              )
            end

            private

            attr_reader :batch, :now, :registration, :state
          end
        end
      end
    end
  end
end
