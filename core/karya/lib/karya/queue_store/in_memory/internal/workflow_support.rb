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
              batch = build_enqueue_batch(batch_id: binding.batch_id, jobs:, now: normalized_now)
              validate_bulk_enqueue_uniqueness(jobs, normalized_now)
              expire_reservations_locked(normalized_now)
              queued_jobs = jobs.map { |job| enqueue_validated_job(job, normalized_now) }
              store_batch(batch)
              state.register_workflow_dependencies(binding.dependency_job_ids_by_job_id)
              BulkMutationReport.new(
                action: :enqueue_many,
                performed_at: normalized_now,
                requested_job_ids: jobs.map(&:id),
                changed_jobs: queued_jobs,
                skipped_jobs: []
              )
            end
          end

          private

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
