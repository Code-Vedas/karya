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
        # Builds the discard transition for dead-lettered workflow-step jobs.
        class DiscardWorkflowStepTransitionBuilder
          def initialize(mutation:, now:)
            @mutation = mutation
            @now = now
          end

          def build
            job = mutation.job
            unless job.state == :dead_letter && job.can_transition_to?(:cancelled)
              return WorkflowStepSkippedJobBuilder.build(mutation:, reason: :ineligible_state)
            end

            job.transition_to(
              :cancelled,
              updated_at: now,
              next_retry_at: nil,
              failure_classification: nil,
              dead_letter_reason: nil,
              dead_lettered_at: nil,
              dead_letter_source_state: nil
            )
          end

          private

          attr_reader :mutation, :now
        end
      end
    end
  end
end
