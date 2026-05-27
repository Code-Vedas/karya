# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Builds and resolves workflow step-to-job bindings.
        class WorkflowStepBindings
          def initialize(definition: nil, step_job_ids: nil, binding: nil, registration: nil, step_ids: nil)
            @definition = definition
            @step_job_ids = step_job_ids
            @binding = binding
            @registration = registration
            @step_ids = step_ids
          end

          def rows
            {
              approval_requirements_by_job_id: approval_requirements,
              interaction_requirements_by_job_id: interaction_requirements,
              child_workflow_ids_by_step_id: child_workflow_ids_by_step,
              compensation_jobs_by_step_id: binding.compensation_jobs_by_step_id
            }.freeze
          end

          def control_job_ids
            normalized_step_ids.map do |step_id|
              registration.step_job_ids.fetch(step_id) do
                raise Workflow::InvalidExecutionError, "unknown workflow step #{step_id.inspect}"
              end
            end.freeze
          end

          private

          attr_reader :definition, :step_job_ids, :binding, :registration, :step_ids

          def approval_requirements
            definition.steps.each_with_object({}) do |workflow_step, requirements|
              approval_name = workflow_step.wait_for_approval
              next unless approval_name

              requirements[step_job_ids.fetch(workflow_step.id)] = { 'name' => approval_name.to_s }.freeze
            end.freeze
          end

          def interaction_requirements
            definition.steps.each_with_object({}) do |workflow_step, requirements|
              requirement = interaction_requirement_for(workflow_step)
              requirements[step_job_ids.fetch(workflow_step.id)] = requirement if requirement
            end.freeze
          end

          def interaction_requirement_for(workflow_step)
            signal_name = workflow_step.wait_for_signal
            return { 'kind' => 'signal', 'name' => signal_name.to_s }.freeze if signal_name

            event_name = workflow_step.wait_for_event
            return { 'kind' => 'event', 'name' => event_name.to_s }.freeze if event_name

            nil
          end

          def child_workflow_ids_by_step
            definition.steps.each_with_object({}) do |workflow_step, child_workflow_ids|
              child_workflow_id = child_workflow_id_for(workflow_step)
              child_workflow_ids[workflow_step.id] = child_workflow_id if child_workflow_id
            end.freeze
          end

          def normalized_step_ids
            raise Workflow::InvalidExecutionError, 'step_ids must be an Array' unless step_ids.is_a?(Array)
            raise Workflow::InvalidExecutionError, 'step_ids must not be empty' if step_ids.empty?

            seen = {}
            step_ids.map do |step_id|
              normalized_step_id = Workflow.send(:normalize_execution_identifier, :step_id, step_id)
              raise Workflow::InvalidExecutionError, "duplicate workflow step #{normalized_step_id.inspect}" if seen.key?(normalized_step_id)

              seen[normalized_step_id] = true
              normalized_step_id
            end.freeze
          end

          def child_workflow_id_for(workflow_step)
            workflow_step.child_workflow
          end
        end
      end
    end
  end
end
