# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Validates whether a failed workflow can be rolled back.
        module RollbackEligibility
          private

          def validate_rollback_snapshot(snapshot, dependency_job_ids_by_job_id)
            eligibility = rollback_snapshot_eligibility(snapshot, dependency_job_ids_by_job_id)
            return if eligibility.eligible?

            raise Workflow::InvalidExecutionError, eligibility.rejection_message
          end

          def rollback_runnable_waiting_job?(job, dependency_job_ids_by_job_id, jobs)
            snapshot = Struct.new(:state, :jobs, :batch_id).new(:failed, jobs, 'rollback-check')
            rollback_snapshot_eligibility(snapshot, dependency_job_ids_by_job_id).runnable_waiting_job?(job)
          end

          def rollback_eligible_snapshot?(snapshot, dependency_job_ids_by_job_id)
            rollback_snapshot_eligibility(snapshot, dependency_job_ids_by_job_id).eligible?
          end

          def rollback_rejection_message(snapshot, dependency_job_ids_by_job_id)
            rollback_snapshot_eligibility(snapshot, dependency_job_ids_by_job_id).rejection_message
          end

          def rollback_snapshot_eligibility(snapshot, dependency_job_ids_by_job_id)
            RollbackSnapshotEligibility.new(snapshot:, dependency_job_ids_by_job_id:)
          end
        end
      end
    end
  end
end
