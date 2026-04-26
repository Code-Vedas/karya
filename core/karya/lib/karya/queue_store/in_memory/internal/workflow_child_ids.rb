# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Builds step-to-child-workflow metadata in definition order.
        class WorkflowChildIds
          def initialize(definition)
            @definition = definition
          end

          def to_h
            definition.steps.each_with_object({}) do |workflow_step, child_workflow_ids|
              StepEntry.new(workflow_step).store_in(child_workflow_ids)
            end.freeze
          end

          private

          attr_reader :definition

          # Adds one declared child workflow id to an accumulator.
          class StepEntry
            def initialize(workflow_step)
              @workflow_step = workflow_step
            end

            def store_in(child_workflow_ids)
              child_workflow_ids[id] = child_workflow if workflow_step.child_workflow?
            end

            private

            attr_reader :workflow_step

            def id
              workflow_step.id
            end

            def child_workflow
              workflow_step.child_workflow
            end
          end

          private_constant :StepEntry
        end
      end
    end
  end
end
