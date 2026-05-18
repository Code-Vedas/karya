# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    module Internal
      module ReferenceQueueStore
        module Internal
          # Owner-local workflow history inspection and journal helpers.
          module WorkflowHistorySupport
            MAX_COMPENSATION_JOB_ID_PREVIEW = 20

            def workflow_history(batch_id:, now:)
              normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)
              normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)

              snapshot_outcome = @mutex.synchronize(persist_if: ->(outcome) { outcome.fetch(:persist) }) do
                recovery_report = recover_in_flight_locked(normalized_now)
                batch = fetch_batch(normalized_batch_id)
                registration = fetch_workflow_registration(batch.id)
                {
                  snapshot: WorkflowHistoryBuilder.new(batch:, registration:, now: normalized_now, state:).to_snapshot,
                  persist: !recovery_report.jobs.empty?
                }
              end
              snapshot_outcome.fetch(:snapshot)
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
              nil
            end

            def record_workflow_step_control(batch_id:, registration:, action:, job_id:, occurred_at:)
              state.register_workflow_history_entry(
                batch_id:,
                kind: :control,
                action:,
                occurred_at:,
                step_id: registration.step_id_by_job_id[job_id],
                job_id:
              )
            end

            def record_workflow_rollback_history(batch_id:, rollback_batch_id:, queued_job_ids:, reason:, occurred_at:)
              rollback_boundary_action = rollback_batch_id ? :rollback_batch_created : :rollback_noop_boundary
              compensation_job_details = CompensationJobDetails.new(queued_job_ids).to_h
              state.register_workflow_history_entry(
                batch_id:,
                kind: :rollback,
                action: :rollback_requested,
                occurred_at:,
                child_batch_id: rollback_batch_id,
                details: compensation_job_details.merge(
                  'reason' => reason,
                  'rollback_batch_created' => (rollback_boundary_action == :rollback_batch_created)
                )
              )
              state.register_workflow_history_entry(
                batch_id:,
                kind: :rollback,
                action: rollback_boundary_action,
                occurred_at:,
                child_batch_id: rollback_batch_id,
                details: compensation_job_details
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

            # Builds bounded rollback details for workflow history entries.
            class CompensationJobDetails
              def initialize(queued_job_ids)
                @queued_job_ids = queued_job_ids
              end

              def to_h
                preview_job_ids = queued_job_ids.first(MAX_COMPENSATION_JOB_ID_PREVIEW)
                total_count = queued_job_ids.length
                {
                  'compensation_job_count' => total_count,
                  'compensation_job_ids_preview' => preview_job_ids,
                  'compensation_job_ids_omitted_count' => total_count - preview_job_ids.length
                }
              end

              private

              attr_reader :queued_job_ids
            end
          end
        end
      end
    end
  end
end
