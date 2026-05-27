# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds durable workflow registration metadata for enqueue operations.
        class WorkflowRegistrationBuilder
          def self.step_job_ids_for(definition, queued_jobs)
            definition.steps.each_with_index.with_object({}) do |(workflow_step, index), ids|
              ids[workflow_step.id] = queued_jobs.fetch(index).id
            end.freeze
          end

          def initialize(operation:, definition:, binding:, queued_jobs:)
            @operation = operation
            @definition = definition
            @binding = binding
            @queued_jobs = queued_jobs
          end

          def build
            step_job_ids = self.class.step_job_ids_for(definition, queued_jobs)
            workflow_rows = operation.send(:workflow_step_id_rows, definition:, step_job_ids:, binding:)
            approval_requirements_by_job_id = workflow_rows.fetch(:approval_requirements_by_job_id)
            interaction_requirements_by_job_id = workflow_rows.fetch(:interaction_requirements_by_job_id)
            child_workflow_ids_by_step_id = workflow_rows.fetch(:child_workflow_ids_by_step_id)
            compensation_jobs_by_step_id = workflow_rows.fetch(:compensation_jobs_by_step_id)

            WorkflowRuntimeSupport::WorkflowRegistration.new(
              definition.id,
              definition.workflow_family,
              definition.workflow_version,
              step_job_ids,
              step_job_ids.invert.freeze,
              binding.dependency_job_ids_by_job_id.freeze,
              approval_requirements_by_job_id,
              interaction_requirements_by_job_id,
              WorkflowRuntimeSupport::InteractionSupportedKeysBuilder.new(
                approval_requirements_by_job_id:,
                interaction_requirements_by_job_id:
              ).to_h,
              compensation_jobs_by_step_id.freeze,
              child_workflow_ids_by_step_id
            ).freeze
          end

          private

          attr_reader :operation, :definition, :binding, :queued_jobs
        end
      end
    end
  end
end
