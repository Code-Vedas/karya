# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds a skipped-job report entry for workflow-step bulk transitions.
        class WorkflowStepSkippedJobBuilder
          def self.build(mutation:, reason:)
            mutation.skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(
              job_id: mutation.job_id,
              reason:,
              state: mutation.job.state
            ).to_h
            nil
          end
        end

        # Guards workflow-step transitions against persisted uniqueness conflicts.
        class WorkflowStepUniquenessConflictGuard
          def initialize(operation:, mutation:, job:, now:)
            @operation = operation
            @mutation = mutation
            @job = job
            @now = now
          end

          def skip_conflict?
            return false unless operation.send(:uniqueness_conflict?, job, mutation.rows, now:, exclude_job_id: mutation.job_id)

            WorkflowStepSkippedJobBuilder.build(mutation:, reason: :uniqueness_conflict)
            true
          end

          private

          attr_reader :operation, :mutation, :job, :now
        end
      end
    end
  end
end
