# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Builds a workflow registration from batch and step rows.
        class RegistrationBuilder
          def initialize(batch_row:, step_rows:)
            @batch_row = batch_row
            @step_rows = step_rows
          end

          def build
            WorkflowRegistration.new(
              batch_row.fetch(:workflow_id),
              batch_row.fetch(:workflow_family),
              batch_row.fetch(:workflow_version),
              step_job_ids,
              step_job_ids.invert.freeze,
              dependency_job_ids_by_job_id,
              approval_requirements_by_job_id,
              interaction_requirements_by_job_id,
              interaction_supported_keys,
              compensation_jobs_by_step_id,
              child_workflow_ids_by_step_id
            ).freeze
          end

          private

          attr_reader :batch_row, :step_rows

          def maps
            @maps ||= RegistrationMapsBuilder.new(step_rows:).to_h
          end

          def step_job_ids
            @step_job_ids ||= maps.fetch(:step_job_ids).freeze
          end

          def dependency_job_ids_by_job_id
            @dependency_job_ids_by_job_id ||= maps.fetch(:dependency_job_ids_by_job_id).freeze
          end

          def approval_requirements_by_job_id
            @approval_requirements_by_job_id ||= maps.fetch(:approval_requirements_by_job_id).freeze
          end

          def interaction_requirements_by_job_id
            @interaction_requirements_by_job_id ||= maps.fetch(:interaction_requirements_by_job_id).freeze
          end

          def interaction_supported_keys
            @interaction_supported_keys ||= InteractionSupportedKeysBuilder.new(
              approval_requirements_by_job_id:,
              interaction_requirements_by_job_id:
            ).to_h
          end

          def compensation_jobs_by_step_id
            @compensation_jobs_by_step_id ||= maps.fetch(:compensation_jobs_by_step_id).freeze
          end

          def child_workflow_ids_by_step_id
            @child_workflow_ids_by_step_id ||= maps.fetch(:child_workflow_ids_by_step_id).freeze
          end
        end
      end
    end
  end
end
