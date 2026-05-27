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
        # Builds the dead-letter transition for workflow-step jobs.
        class DeadLetterWorkflowStepTransitionBuilder
          def initialize(mutation:, now:, reason:)
            @mutation = mutation
            @now = now
            @reason = reason
          end

          def build
            job = mutation.job
            return WorkflowStepSkippedJobBuilder.build(mutation:, reason: :ineligible_state) unless job.can_transition_to?(:dead_letter)

            job.transition_to(
              :dead_letter,
              updated_at: now,
              next_retry_at: nil,
              failure_classification: job.failure_classification,
              dead_letter_reason: reason,
              dead_lettered_at: now,
              dead_letter_source_state: job.state
            )
          end

          private

          attr_reader :mutation, :now, :reason
        end
      end
    end
  end
end
