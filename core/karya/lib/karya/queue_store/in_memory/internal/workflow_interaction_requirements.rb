# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        module WorkflowSupport
          # Maps workflow signal/event gates by concrete workflow job id.
          class InteractionRequirements
            def initialize(definition:, step_job_ids:)
              @definition = definition
              @step_job_ids = step_job_ids
            end

            def to_h
              definition.steps.each_with_object({}) do |workflow_step, requirements|
                requirement = StepRequirement.new(workflow_step).to_h
                next unless requirement

                requirements[step_job_ids.fetch(workflow_step.id)] = requirement
              end.freeze
            end

            private

            attr_reader :definition, :step_job_ids

            # Resolves one workflow step's optional interaction gate.
            class StepRequirement
              def initialize(workflow_step)
                @workflow_step = workflow_step
              end

              def to_h
                wait_for_signal = workflow_step.wait_for_signal
                return { kind: :signal, name: wait_for_signal }.freeze if wait_for_signal

                wait_for_event = workflow_step.wait_for_event
                return { kind: :event, name: wait_for_event }.freeze if wait_for_event

                nil
              end

              private

              attr_reader :workflow_step
            end

            private_constant :StepRequirement
          end
        end
      end
    end
  end
end
