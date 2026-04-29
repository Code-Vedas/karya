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
          # Maps workflow approval checkpoints by concrete workflow job id.
          class ApprovalRequirements
            def initialize(definition:, step_job_ids:)
              @definition = definition
              @step_job_ids = step_job_ids
            end

            def to_h
              definition.steps.each_with_object({}) do |workflow_step, requirements|
                approval_name = workflow_step.wait_for_approval
                next unless approval_name

                requirements[step_job_ids.fetch(workflow_step.id)] = { name: approval_name }.freeze
              end.freeze
            end

            private

            attr_reader :definition, :step_job_ids
          end
        end
      end
    end
  end
end
