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
          def enqueue_workflow(definition:, jobs_by_step_id:, batch_id:, now:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)

            @mutex.synchronize do
              binding = Workflow.send(:build_execution_binding, definition:, jobs_by_step_id:, batch_id:)
              jobs = binding.jobs
              workflow_batch_id = binding.batch_id
              batch = build_enqueue_batch(batch_id: workflow_batch_id, jobs:, now: normalized_now)
              validate_bulk_enqueue_uniqueness(jobs, normalized_now)
              expire_reservations_locked(normalized_now)
              queued_jobs = jobs.map { |job| enqueue_validated_job(job, normalized_now) }
              dependency_job_ids_by_job_id = binding.dependency_job_ids_by_job_id
              store_batch(batch)
              state.workflow_dependency_job_ids_by_job_id.merge!(dependency_job_ids_by_job_id)
              state.register_workflow(
                batch_id: workflow_batch_id,
                workflow_id: definition.id,
                step_job_ids: StepJobIds.new(definition:, jobs:).to_h,
                dependency_job_ids_by_job_id:
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

          def workflow_snapshot(batch_id:, now:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)
            normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)

            @mutex.synchronize do
              recover_in_flight_locked(normalized_now)
              batch = fetch_batch(normalized_batch_id)
              workflow_batch_id = batch.id
              registration = fetch_workflow_registration(workflow_batch_id)
              jobs = batch.job_ids.map { |job_id| state.jobs_by_id.fetch(job_id) }
              Workflow::Snapshot.new(
                workflow_id: registration.workflow_id,
                batch_id: workflow_batch_id,
                captured_at: normalized_now,
                step_job_ids: registration.step_job_ids,
                dependency_job_ids_by_job_id: registration.dependency_job_ids_by_job_id,
                jobs:
              )
            end
          end

          private

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
          private_constant :StepJobIds

          def fetch_workflow_registration(batch_id)
            registration = state.workflow_registrations_by_batch_id[batch_id]
            return registration if registration

            raise Workflow::InvalidExecutionError, "batch #{batch_id.inspect} is not a workflow batch"
          end

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
