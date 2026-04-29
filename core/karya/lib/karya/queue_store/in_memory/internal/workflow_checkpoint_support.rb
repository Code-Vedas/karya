# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Owner-local workflow pause/resume and approval checkpoint controls.
        module WorkflowCheckpointSupport
          def pause_workflow(batch_id:, now:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)
            normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)

            @mutex.synchronize do
              recover_in_flight_locked(normalized_now)
              workflow_batch_id = fetch_workflow_control_batch_id(normalized_batch_id, normalized_now)
              state.mark_workflow_pause_requested(batch_id: workflow_batch_id, now: normalized_now)
              BulkMutationReport.new(
                action: :pause_workflow,
                performed_at: normalized_now,
                requested_job_ids: [],
                changed_jobs: [],
                skipped_jobs: []
              )
            end
          end

          def resume_workflow(batch_id:, now:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)
            normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)

            @mutex.synchronize do
              recover_in_flight_locked(normalized_now)
              workflow_batch_id = fetch_workflow_control_batch_id(normalized_batch_id, normalized_now)
              state.clear_workflow_pause_requested(workflow_batch_id)
              BulkMutationReport.new(
                action: :resume_workflow,
                performed_at: normalized_now,
                requested_job_ids: [],
                changed_jobs: [],
                skipped_jobs: []
              )
            end
          end

          def approve_workflow_checkpoints(batch_id:, step_ids:, now:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)

            @mutex.synchronize do
              Karya::Internal::BulkMutation::ReportBuilder.new(
                action: :approve_workflow_checkpoints,
                job_ids: workflow_approval_control_job_ids(batch_id, step_ids, now: normalized_now),
                now: normalized_now
              ).to_report do |job_id, _changed_jobs, _skipped_jobs|
                state.register_workflow_approval_approved(job_id:, decided_at: normalized_now)
              end
            end
          end

          def reject_workflow_checkpoints(batch_id:, step_ids:, now:, reason:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)
            normalized_reason = normalize_approval_rejection_reason(reason)

            @mutex.synchronize do
              Karya::Internal::BulkMutation::ReportBuilder.new(
                action: :reject_workflow_checkpoints,
                job_ids: workflow_approval_control_job_ids(batch_id, step_ids, now: normalized_now),
                now: normalized_now
              ).to_report do |job_id, changed_jobs, skipped_jobs|
                state.register_workflow_approval_rejected(job_id:, decided_at: normalized_now, reason: normalized_reason)
                cancel_requested_job(job_id, normalized_now, changed_jobs, skipped_jobs)
              end
            end
          end

          private

          def normalize_approval_rejection_reason(reason)
            normalize_rollback_reason(reason)
          end

          def fetch_workflow_control_batch_id(normalized_batch_id, now)
            batch = fetch_batch(normalized_batch_id)
            workflow_batch_id = batch.id
            registration = fetch_workflow_registration(workflow_batch_id)
            snapshot = build_workflow_snapshot(
              batch:,
              registration:,
              jobs: fetch_batch_jobs(batch),
              now:
            )
            validate_workflow_control_target(snapshot, workflow_batch_id)
            workflow_batch_id
          end

          def validate_workflow_control_target(snapshot, batch_id)
            return unless WorkflowSupport::WORKFLOW_INTERACTION_TERMINAL_STATES.include?(snapshot.state)

            raise Workflow::InvalidExecutionError, "workflow batch #{batch_id.inspect} is terminal and cannot be controlled"
          end

          def workflow_approval_control_job_ids(batch_id, step_ids, now:)
            normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)
            batch = fetch_batch(normalized_batch_id)
            registration = fetch_workflow_registration(batch.id)
            jobs = fetch_batch_jobs(batch)
            snapshot = build_workflow_snapshot(batch:, registration:, jobs:, now:)
            workflow_control_job_ids(batch_id, step_ids).tap do |job_ids|
              validate_workflow_approval_targets(snapshot, registration, job_ids)
            end
          end

          def validate_workflow_approval_targets(snapshot, registration, job_ids)
            step_ids_by_job_id = registration.step_job_ids.invert
            job_ids.each do |job_id|
              step_id = step_ids_by_job_id[job_id]
              approval_requirement = registration.approval_requirements_by_job_id[job_id]
              raise Workflow::InvalidExecutionError, "workflow step #{step_id.inspect} is not an approval checkpoint" unless approval_requirement

              step_snapshot = snapshot.fetch_step(step_id)
              next if step_snapshot.awaiting_approval?

              raise Workflow::InvalidExecutionError, "workflow step #{step_snapshot.step_id.inspect} is not awaiting approval"
            end
          end

          def workflow_approval_satisfied?(job)
            job_id = job.id
            requirement = state.workflow_approval_requirement_for(job_id)
            return true unless requirement

            decision = state.workflow_approval_decision_for(job_id)
            return false if decision&.state == :rejected
            return true if decision&.state == :approved

            batch_id = state.batch_id_by_job_id[job_id]
            state.workflow_interaction_delivered?(batch_id:, kind: :signal, name: requirement.fetch(:name))
          end

          def workflow_paused?(job)
            batch_id = state.batch_id_by_job_id[job.id]
            !!(batch_id && state.workflow_pause_requested_at(batch_id))
          end
        end
      end
    end
  end
end
