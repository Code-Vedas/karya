# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'workflow_step_transition_support'

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds the retry transition for failed or retry-pending workflow-step jobs.
        class RetryWorkflowStepTransitionBuilder
          def initialize(operation:, mutation:, now:)
            @operation = operation
            @mutation = mutation
            @now = now
          end

          def build
            retried_job = retried_job_for
            return WorkflowStepSkippedJobBuilder.build(mutation:, reason: :ineligible_state) unless retried_job
            return if WorkflowStepUniquenessConflictGuard.new(operation:, mutation:, job: retried_job, now:).skip_conflict?

            retried_job
          end

          private

          attr_reader :operation, :mutation, :now

          def retried_job_for
            job = mutation.job
            case job.state
            when :failed
              job.transition_to(:retry_pending, updated_at: now, next_retry_at: now).transition_to(
                :queued,
                updated_at: now,
                next_retry_at: nil,
                failure_classification: nil
              )
            when :retry_pending
              job.transition_to(:queued, updated_at: now, next_retry_at: nil, failure_classification: nil)
            end
          end
        end
      end
    end
  end
end
