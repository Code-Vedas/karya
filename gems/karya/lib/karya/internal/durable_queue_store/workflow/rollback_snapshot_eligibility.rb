# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Evaluates whether a workflow snapshot can be rolled back given current dependency state.
        class RollbackSnapshotEligibility
          def initialize(snapshot:, dependency_job_ids_by_job_id:)
            @snapshot = snapshot
            @dependency_job_ids_by_job_id = dependency_job_ids_by_job_id
          end

          def eligible?
            failed_state? && jobs.none? { |job| active_job?(job) }
          end

          def rejection_message
            rendered_batch_id = batch_id.inspect
            return "workflow batch #{rendered_batch_id} must be failed before rollback" unless failed_state?
            return "workflow batch #{rendered_batch_id} can be rolled back" if eligible?

            "workflow batch #{rendered_batch_id} has active jobs and cannot be rolled back"
          end

          def runnable_waiting_job?(job)
            return false unless waiting_job_state?(job)

            dependency_job_ids(job).all? { |dependency_job_id| succeeded_job_ids.include?(dependency_job_id) }
          end

          private

          attr_reader :snapshot, :dependency_job_ids_by_job_id

          def batch_id
            snapshot.batch_id
          end

          def failed_state?
            snapshot.state == :failed
          end

          def jobs
            snapshot.jobs
          end

          def active_job?(job)
            ACTIVE_JOB_STATES.include?(job.state) || runnable_waiting_job?(job)
          end

          def waiting_job_state?(job)
            WAITING_JOB_STATES.include?(job.state)
          end

          def dependency_job_ids(job)
            Array(dependency_job_ids_by_job_id.fetch(job.id, []))
          end

          def succeeded_job_ids
            @succeeded_job_ids ||= jobs.select { |job| job.state == :succeeded }.map(&:id)
          end
        end
      end
    end
  end
end
