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
        # Builds the replay transition for dead-lettered workflow-step jobs.
        class ReplayWorkflowStepTransitionBuilder
          def initialize(operation:, mutation:, now:)
            @operation = operation
            @mutation = mutation
            @now = now
          end

          def build
            job = mutation.job
            return WorkflowStepSkippedJobBuilder.build(mutation:, reason: :ineligible_state) unless job.state == :dead_letter && job.can_transition_to?(:queued)

            recovered = job.transition_to(
              :queued,
              updated_at: now,
              next_retry_at: nil,
              failure_classification: nil,
              dead_letter_reason: nil,
              dead_lettered_at: nil,
              dead_letter_source_state: nil
            )
            return if WorkflowStepUniquenessConflictGuard.new(operation:, mutation:, job: recovered, now:).skip_conflict?

            recovered
          end

          private

          attr_reader :operation, :mutation, :now
        end
      end
    end
  end
end
