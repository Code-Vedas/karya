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
              batch = build_enqueue_batch(batch_id: workflow_batch_id, jobs:, now: normalized_now)
              validate_bulk_enqueue_uniqueness(jobs, normalized_now)
              expire_reservations_locked(normalized_now)
              queued_jobs = jobs.map { |job| enqueue_validated_job(job, normalized_now) }
              dependency_job_ids_by_job_id = binding.dependency_job_ids_by_job_id
              store_batch(batch)
              state.register_workflow_dependencies(dependency_job_ids_by_job_id)
              state.register_workflow(
                batch_id: workflow_batch_id,
                workflow_id: definition.id,
                step_job_ids: StepJobIds.new(definition:, jobs:).to_h,
                dependency_job_ids_by_job_id:,
                compensation_jobs_by_step_id: binding.compensation_jobs_by_step_id
              )
              BulkMutationReport.new(
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
            normalized_reason = Karya::Internal::DeadLetterReason.normalize(reason, error_class: Workflow::InvalidExecutionError)
            normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)

            @mutex.synchronize do
              rollback = prepare_rollback(normalized_batch_id, normalized_now)
              rollback_plan = rollback.plan
              rollback_jobs = rollback_plan.jobs
              rollback_batch = rollback.batch
              validate_bulk_enqueue_uniqueness(rollback_jobs, normalized_now)
              expire_reservations_locked(normalized_now)
              queued_jobs = rollback_jobs.map { |job| enqueue_validated_job(job, normalized_now) }
              queued_job_ids = queued_jobs.map(&:id)
              store_batch(rollback_batch) if rollback_batch
              state.register_workflow_dependencies(rollback_plan.dependency_job_ids_by_job_id)
              state.register_workflow_rollback(
                batch_id: rollback.workflow_batch_id,
                rollback_batch_id: rollback.rollback_batch_id,
                reason: normalized_reason,
                requested_at: normalized_now,
                compensation_job_ids: queued_job_ids
              )
              BulkMutationReport.new(
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
              workflow_snapshot_for(batch:, registration:, jobs:, now: normalized_now)
            end
          end

          private

          # Groups the validated rollback batch and enqueue plan.
          Rollback = Struct.new(:workflow_batch_id, :rollback_batch_id, :batch, :plan)

          # Builds a deterministic rollback batch id for one workflow batch.
          class RollbackBatchId
            def initialize(batch_id)
              @batch_id = batch_id
            end

            def to_s
              "#{batch_id}.rollback"
            end

            private

            attr_reader :batch_id
          end

          # Immutable rollback enqueue plan.
          class RollbackPlan
            # Immutable compensation jobs and dependency metadata.
            Plan = Struct.new(:jobs, :dependency_job_ids_by_job_id)
            private_constant :Plan

            def initialize(registration:, jobs:)
              @registration = registration
              @jobs_by_id = jobs.to_h { |job| [job.id, job] }
            end

            def to_plan
              compensation_jobs = ordered_compensation_jobs
              Plan.new(compensation_jobs.freeze, RollbackDependencies.new(compensation_jobs).to_h).freeze
            end

            private

            attr_reader :jobs_by_id, :registration

            def ordered_compensation_jobs
              step_job_ids = registration.step_job_ids
              step_job_ids.keys.reverse.filter_map do |step_id|
                primary_job = jobs_by_id.fetch(step_job_ids.fetch(step_id))
                next unless primary_job.state == :succeeded

                registration.compensation_jobs_by_step_id[step_id]
              end
            end
          end

          # Builds serial dependency metadata for rollback compensation jobs.
          class RollbackDependencies
            def initialize(jobs)
              @jobs = jobs
            end

            def to_h
              previous_job_id = nil
              jobs.each_with_object({}) do |job, dependencies|
                job_id = job.id
                dependencies[job_id] = previous_job_id ? [previous_job_id].freeze : []
                previous_job_id = job_id
              end.freeze
            end

            private

            attr_reader :jobs
          end

          # Builds step-to-job metadata in definition order.
          class StepJobIds
            def initialize(definition:, jobs:)
              @definition = definition
              @jobs = jobs
            end

            def to_h
              definition.steps.each_with_object({}).with_index do |(workflow_step, step_job_ids), index|
                step_job_ids[workflow_step.id] = jobs.fetch(index).id
              end.freeze
            end

            private

            attr_reader :definition, :jobs
          end
          private_constant :Rollback, :RollbackBatchId, :RollbackDependencies, :RollbackPlan, :StepJobIds

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
            snapshot = workflow_snapshot_for(batch:, registration:, jobs:, now:)
            RollbackState.new(snapshot).validate
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

          def workflow_snapshot_for(batch:, registration:, jobs:, now:)
            WorkflowSnapshotBuilder.new(
              batch:,
              registration:,
              jobs:,
              now:,
              dependency_job_ids_by_job_id: registration.dependency_job_ids_by_job_id
            ).to_snapshot
          end

          def raise_duplicate_rollback(batch_id)
            return unless state.workflow_rollbacks_by_batch_id[batch_id]

            raise Workflow::InvalidExecutionError, "workflow batch #{batch_id.inspect} has already been rolled back"
          end

          # Builds workflow snapshots from stored workflow metadata.
          class WorkflowSnapshotBuilder
            def initialize(batch:, registration:, jobs:, now:, dependency_job_ids_by_job_id:)
              @batch = batch
              @registration = registration
              @jobs = jobs
              @now = now
              @dependency_job_ids_by_job_id = dependency_job_ids_by_job_id
            end

            def to_snapshot
              Workflow::Snapshot.new(
                workflow_id: registration.workflow_id,
                batch_id: batch.id,
                captured_at: now,
                step_job_ids: registration.step_job_ids,
                dependency_job_ids_by_job_id:,
                jobs:
              )
            end

            private

            attr_reader :batch, :dependency_job_ids_by_job_id, :jobs, :now, :registration
          end

          # Validates rollback state eligibility.
          class RollbackState
            def initialize(snapshot)
              @snapshot = snapshot
            end

            def validate
              return if snapshot.state == :failed

              raise Workflow::InvalidExecutionError, "workflow batch #{snapshot.batch_id.inspect} must be failed before rollback"
            end

            private

            attr_reader :snapshot
          end
          private_constant :RollbackState, :WorkflowSnapshotBuilder

          def workflow_dependencies_satisfied?(job)
            prerequisite_job_ids = state.workflow_dependency_job_ids_by_job_id[job.id]
            return true unless prerequisite_job_ids

            prerequisite_job_ids.all? do |prerequisite_job_id|
              prerequisite_job = state.jobs_by_id[prerequisite_job_id]
              prerequisite_job && prerequisite_job.state == :succeeded
            end
          end
        end
      end
    end
  end
end
