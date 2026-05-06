# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Owner-local workflow enqueue and prerequisite readiness support.
        module WorkflowSupport
          WORKFLOW_INTERACTION_TERMINAL_STATES = %i[succeeded failed cancelled].freeze
          def enqueue_workflow(definition:, jobs_by_step_id:, batch_id:, now:, compensation_jobs_by_step_id: {})
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)

            @mutex.synchronize do
              binding = Workflow.send(
                :build_compensated_execution_binding,
                definition:,
                jobs_by_step_id:,
                batch_id:,
                compensation_jobs_by_step_id:
              )
              jobs = binding.jobs
              workflow_batch_id = binding.batch_id
              store_batch(validate_workflow_enqueue_jobs(workflow_batch_id:, jobs:, now: normalized_now))
              expire_reservations_locked(normalized_now)
              queued_jobs = jobs.map { |job| enqueue_validated_job(job, normalized_now) }
              step_job_ids = StepJobIds.new(definition:, jobs:).to_h
              register_workflow_enqueue(
                definition:,
                binding:,
                workflow_batch_id:,
                step_job_ids:,
                occurred_at: normalized_now
              )
              Karya::QueueStore::Internal::BulkMutationReport.new(
                action: :enqueue_many,
                performed_at: normalized_now,
                requested_job_ids: jobs.map(&:id),
                changed_jobs: queued_jobs,
                skipped_jobs: []
              )
            end
          end

          def rollback_workflow(batch_id:, now:, reason:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)
            normalized_reason = normalize_rollback_reason(reason)
            normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)

            @mutex.synchronize do
              expire_reservations_locked(normalized_now)
              rollback = prepare_rollback(normalized_batch_id, normalized_now)
              rollback_plan = rollback.plan
              rollback_jobs = rollback_plan.jobs
              rollback_batch = rollback.batch
              workflow_batch_id = rollback.workflow_batch_id
              validate_bulk_enqueue_uniqueness(rollback_jobs, normalized_now)
              queued_jobs = rollback_jobs.map { |job| enqueue_validated_job(job, normalized_now) }
              queued_job_ids = queued_jobs.map(&:id)
              store_batch(rollback_batch) if rollback_batch
              state.register_workflow_dependencies(rollback_plan.dependency_job_ids_by_job_id)
              state.register_workflow_rollback(
                batch_id: workflow_batch_id,
                rollback_batch_id: rollback.rollback_batch_id,
                reason: normalized_reason,
                requested_at: normalized_now,
                compensation_job_ids: queued_job_ids
              )
              record_workflow_rollback_history(
                batch_id: workflow_batch_id,
                rollback_batch_id: rollback_batch&.id,
                queued_job_ids:,
                reason: normalized_reason,
                occurred_at: normalized_now
              )
              Karya::QueueStore::Internal::BulkMutationReport.new(
                action: :rollback_workflow,
                performed_at: normalized_now,
                requested_job_ids: queued_job_ids,
                changed_jobs: queued_jobs,
                skipped_jobs: []
              )
            end
          end

          def workflow_snapshot(batch_id:, now:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)
            normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)

            @mutex.synchronize do
              recover_in_flight_locked(normalized_now)
              batch = fetch_batch(normalized_batch_id)
              workflow_batch_id = batch.id
              registration = fetch_workflow_registration(workflow_batch_id)
              jobs = fetch_batch_jobs(batch)
              build_workflow_snapshot(batch:, registration:, jobs:, now: normalized_now)
            end
          end

          def retry_workflow_steps(batch_id:, step_ids:, now:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)

            @mutex.synchronize do
              workflow_control_report(
                action: :retry_workflow_steps,
                batch_id:,
                step_ids:,
                now: normalized_now
              ) do |job_id, changed_jobs, skipped_jobs|
                retry_requested_job(job_id, normalized_now, changed_jobs, skipped_jobs)
              end
            end
          end

          def dead_letter_workflow_steps(batch_id:, step_ids:, now:, reason:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)
            normalized_reason = normalize_dead_letter_reason(reason)

            @mutex.synchronize do
              workflow_control_report(
                action: :dead_letter_workflow_steps,
                batch_id:,
                step_ids:,
                now: normalized_now
              ) do |job_id, changed_jobs, skipped_jobs|
                dead_letter_requested_job(job_id, normalized_now, normalized_reason, changed_jobs, skipped_jobs)
              end
            end
          end

          def replay_workflow_steps(batch_id:, step_ids:, now:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)

            @mutex.synchronize do
              workflow_control_report(
                action: :replay_workflow_steps,
                batch_id:,
                step_ids:,
                now: normalized_now
              ) do |job_id, changed_jobs, skipped_jobs|
                replay_dead_letter_job(job_id, normalized_now, changed_jobs, skipped_jobs)
              end
            end
          end

          def retry_dead_letter_workflow_steps(batch_id:, step_ids:, now:, next_retry_at:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)
            normalized_next_retry_at = normalize_time(:next_retry_at, next_retry_at, error_class: Workflow::InvalidExecutionError)

            @mutex.synchronize do
              workflow_control_report(
                action: :retry_dead_letter_workflow_steps,
                batch_id:,
                step_ids:,
                now: normalized_now
              ) do |job_id, changed_jobs, skipped_jobs|
                retry_dead_letter_job(job_id, normalized_now, normalized_next_retry_at, changed_jobs, skipped_jobs)
              end
            end
          end

          def discard_workflow_steps(batch_id:, step_ids:, now:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)

            @mutex.synchronize do
              workflow_control_report(
                action: :discard_workflow_steps,
                batch_id:,
                step_ids:,
                now: normalized_now
              ) do |job_id, changed_jobs, skipped_jobs|
                discard_dead_letter_job(job_id, normalized_now, changed_jobs, skipped_jobs)
              end
            end
          end

          private

          def validate_workflow_enqueue_jobs(workflow_batch_id:, jobs:, now:)
            validate_bulk_enqueue_uniqueness(jobs, now)
            build_enqueue_batch(batch_id: workflow_batch_id, jobs:, now:)
          end

          def register_workflow_enqueue(definition:, binding:, workflow_batch_id:, step_job_ids:, occurred_at:)
            dependency_job_ids_by_job_id = binding.dependency_job_ids_by_job_id
            state.register_workflow_dependencies(dependency_job_ids_by_job_id)
            registration = state.register_workflow(**WorkflowRegistrationPayload.new(
              definition:,
              binding:,
              workflow_batch_id:,
              step_job_ids:,
              dependency_job_ids_by_job_id:
            ).to_h)
            record_workflow_registration_history(batch_id: workflow_batch_id, registration:, occurred_at:)
            registration
          end

          def normalize_dead_letter_reason(reason)
            Karya::Internal::DeadLetterReason.normalize(reason, error_class: Workflow::InvalidExecutionError)
          rescue Workflow::InvalidExecutionError => e
            raise Workflow::InvalidExecutionError, e.message.gsub('dead_letter_reason', 'reason'), cause: e
          end

          def normalize_rollback_reason(reason)
            max_length = Karya::Internal::DeadLetterReason::MAX_LENGTH
            too_long_message = "reason must be at most #{max_length} characters"

            raise Workflow::InvalidExecutionError, 'reason must be a String' unless reason.is_a?(String)

            normalized_reason = reason.strip
            raise Workflow::InvalidExecutionError, 'reason must be present' if normalized_reason.empty?
            raise Workflow::InvalidExecutionError, too_long_message if normalized_reason.length > max_length

            normalized_reason.freeze
          end

          def fetch_workflow_registration(batch_id)
            registration = state.workflow_registrations_by_batch_id[batch_id]
            return registration if registration

            raise Workflow::InvalidExecutionError, "batch #{batch_id.inspect} is not a workflow batch"
          end

          def prepare_rollback(batch_id, now)
            batch = fetch_batch(batch_id)
            workflow_batch_id = batch.id
            registration = fetch_workflow_registration(workflow_batch_id)
            raise_duplicate_rollback(workflow_batch_id)
            jobs = fetch_batch_jobs(batch)
            snapshot = build_workflow_snapshot(batch:, registration:, jobs:, now:)
            RollbackState.new(snapshot, registration.dependency_job_ids_by_job_id).validate
            plan = RollbackPlan.new(registration:, jobs:).to_plan
            rollback_batch_id = RollbackBatchId.new(workflow_batch_id).to_s
            rollback_batch = build_rollback_batch(batch_id: rollback_batch_id, jobs: plan.jobs, now:)
            Rollback.new(workflow_batch_id, rollback_batch_id, rollback_batch, plan).freeze
          end

          def build_rollback_batch(batch_id:, jobs:, now:)
            if jobs.empty?
              raise_duplicate_batch(batch_id)
              return nil
            end

            build_enqueue_batch(batch_id:, jobs:, now:)
          end

          def raise_duplicate_batch(batch_id)
            return unless state.batches_by_id.key?(batch_id) || workflow_rollback_batch_id?(batch_id)

            raise Workflow::DuplicateBatchError, "batch #{batch_id.inspect} already exists"
          end

          def raise_duplicate_rollback(batch_id)
            return unless state.workflow_rollbacks_by_batch_id[batch_id]

            raise Workflow::InvalidExecutionError, "workflow batch #{batch_id.inspect} has already been rolled back"
          end

          def workflow_control_report(action:, batch_id:, step_ids:, now:, &block)
            normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)
            batch = fetch_batch(normalized_batch_id)
            workflow_batch_id = batch.id
            registration = fetch_workflow_registration(workflow_batch_id)
            Karya::Internal::BulkMutation::ReportBuilder.new(
              action:,
              job_ids: WorkflowControlTargets.new(registration:, step_ids:).job_ids,
              now:
            ).to_report do |job_id, changed_jobs, skipped_jobs|
              changed_before = changed_jobs.length
              block.yield(job_id, changed_jobs, skipped_jobs)
              changed_job = changed_jobs.fetch(changed_before, nil)
              next unless changed_job

              record_workflow_step_control(
                batch_id: workflow_batch_id,
                registration:,
                action:,
                job_id: changed_job.id,
                occurred_at: now
              )
            end
          end

          def workflow_control_job_ids(batch_id, step_ids)
            normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)
            batch = fetch_batch(normalized_batch_id)
            registration = fetch_workflow_registration(batch.id)
            WorkflowControlTargets.new(registration:, step_ids:).job_ids
          end

          # Builds public child workflow relationship snapshots from store metadata.
          class ChildWorkflowSnapshotBuilder
            def initialize(relationship:, resolver:)
              @relationship = relationship
              @resolver = resolver
            end

            def to_snapshot
              Workflow::ChildWorkflowSnapshot.new(
                parent_workflow_id: relationship.parent_workflow_id,
                parent_workflow_family: relationship.parent_workflow_family,
                parent_workflow_version: relationship.parent_workflow_version,
                parent_batch_id: relationship.parent_batch_id,
                parent_step_id: relationship.parent_step_id,
                parent_job_id: relationship.parent_job_id,
                child_workflow_id: relationship.child_workflow_id,
                child_workflow_family: relationship.child_workflow_family,
                child_workflow_version: relationship.child_workflow_version,
                child_batch_id: relationship.child_batch_id,
                child_state:
              )
            end

            private

            attr_reader :relationship, :resolver

            def child_state
              resolver.resolve(relationship.child_batch_id)
            end
          end

          # Converts owner-local rollback storage into public workflow inspection.
          class RollbackSnapshotAttributes
            def initialize(attributes)
              @attributes = attributes
            end

            def to_snapshot
              Workflow::RollbackSnapshot.new(
                workflow_batch_id: fetch(:batch_id),
                rollback_batch_id: fetch(:rollback_batch_id),
                reason: fetch(:reason),
                requested_at: fetch(:requested_at),
                compensation_job_ids: fetch(:compensation_job_ids)
              )
            end

            private

            attr_reader :attributes

            def fetch(name)
              attributes.fetch(name)
            end
          end

          # Validates rollback state eligibility.
          class RollbackState
            ACTIVE_JOB_STATES = %i[reserved running retry_pending].freeze
            WAITING_JOB_STATES = %i[queued submission].freeze

            def initialize(snapshot, dependency_job_ids_by_job_id)
              @snapshot = snapshot
              @dependency_job_ids_by_job_id = dependency_job_ids_by_job_id
              @jobs_by_id = snapshot.jobs.to_h { |job| [job.id, job] }
            end

            def validate
              return if failed_snapshot? && !active_jobs?

              raise Workflow::InvalidExecutionError, validation_error_message
            end

            private

            attr_reader :dependency_job_ids_by_job_id, :jobs_by_id, :snapshot

            def failed_snapshot?
              snapshot.state == :failed
            end

            def active_jobs?
              snapshot.jobs.any? { |job| active_job?(job) }
            end

            def active_job?(job)
              ACTIVE_JOB_STATES.include?(job.state) || runnable_waiting_job?(job)
            end

            def runnable_waiting_job?(job)
              WAITING_JOB_STATES.include?(job.state) && dependencies_satisfied?(job)
            end

            def dependencies_satisfied?(job)
              dependency_job_ids_by_job_id.fetch(job.id, []).all? do |dependency_job_id|
                dependency_job = jobs_by_id[dependency_job_id]
                dependency_job && dependency_job.state == :succeeded
              end
            end

            def validation_error_message
              batch_id = snapshot.batch_id.inspect
              return "workflow batch #{batch_id} must be failed before rollback" unless failed_snapshot?

              "workflow batch #{batch_id} has active jobs and cannot be rolled back"
            end
          end
          private_constant :ChildWorkflowSnapshotBuilder,
                           :RollbackSnapshotAttributes,
                           :RollbackState,
                           :WorkflowRegistrationPayload,
                           :WorkflowSnapshotBuilder

          def workflow_dependencies_satisfied?(job, now:)
            prerequisite_job_ids = state.workflow_dependency_job_ids_for(job.id)
            return false if workflow_paused?(job)
            return false unless workflow_child_satisfied?(job, now:)
            return false unless workflow_interaction_satisfied?(job)
            return false unless workflow_approval_satisfied?(job)
            return true unless prerequisite_job_ids

            prerequisite_job_ids.all? do |prerequisite_job_id|
              prerequisite_job = state.jobs_by_id[prerequisite_job_id]
              prerequisite_job && prerequisite_job.state == :succeeded
            end
          end

          def workflow_child_satisfied?(job, now:)
            job_id = job.id
            workflow_children = state.workflow_children
            child_workflow_id = workflow_children.expected_child_workflow_id_by_job_id[job_id]
            return true unless child_workflow_id

            relationship = workflow_children.for_parent_job(job_id)
            return false unless relationship

            child_workflow_state(relationship.child_batch_id, now:) == :succeeded
          end

          def workflow_interaction_satisfied?(job)
            job_id = job.id
            batch_id = state.batch_id_by_job_id[job_id]
            return true unless batch_id

            registration = state.workflow_registrations_by_batch_id[batch_id]
            return true unless registration

            requirement = registration.interaction_requirements_by_job_id[job_id]
            return true unless requirement

            state.workflow_interaction_delivered?(
              batch_id:,
              kind: requirement.fetch(:kind),
              name: requirement.fetch(:name)
            )
          end

          def build_workflow_snapshot(batch:, registration:, jobs:, now:)
            WorkflowSnapshotBuilder.new(batch:, registration:, jobs:, now:, state:).to_snapshot
          end
        end
      end
    end
  end
end
