# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Selects the current workflow step ids from a snapshot step set.
        class CurrentStepSelector
          def initialize(steps:)
            @steps = steps
          end

          def call
            active_step_ids = active_steps.map(&:step_id).freeze
            return active_step_ids unless active_step_ids.empty?

            ready_step_ids = ready_steps.map(&:step_id).freeze
            return ready_step_ids unless ready_step_ids.empty?

            blocked_steps.map(&:step_id).freeze
          end

          private

          attr_reader :steps

          def active_steps
            @active_steps ||= steps.select(&:active?)
          end

          def ready_steps
            @ready_steps ||= steps.select(&:ready?)
          end

          def blocked_steps
            @blocked_steps ||= steps.select do |step|
              step.blocked? && step.prerequisite_states.values.all?(:succeeded)
            end
          end
        end
      end
    end
  end
end
