# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Builds workflow registration maps from durable workflow-step rows.
        class RegistrationMapsBuilder
          def initialize(step_rows:)
            @step_rows = step_rows
          end

          def to_h
            step_rows.each_with_object(empty_maps) do |step_row, maps|
              merge_step(maps, step_row)
            end
          end

          private

          attr_reader :step_rows

          def empty_maps
            {
              step_job_ids: {},
              dependency_job_ids_by_job_id: {},
              approval_requirements_by_job_id: {},
              interaction_requirements_by_job_id: {},
              compensation_jobs_by_step_id: {},
              child_workflow_ids_by_step_id: {}
            }
          end

          def merge_step(maps, step_row)
            step_id = step_row.fetch(:step_id)
            job_id = step_row.fetch(:job_id)
            metadata = decoded_metadata(step_row)
            maps.fetch(:step_job_ids)[step_id] = job_id
            maps.fetch(:dependency_job_ids_by_job_id)[job_id] = Array(PayloadCodec.decode(step_row.fetch(:dependency_payload))).freeze
            assign_requirement(maps.fetch(:approval_requirements_by_job_id), job_id, metadata_value(metadata, 'approval_requirement'))
            assign_requirement(maps.fetch(:interaction_requirements_by_job_id), job_id, metadata_value(metadata, 'interaction_requirement'))
            assign_value(maps.fetch(:compensation_jobs_by_step_id), step_id, metadata_value(metadata, 'compensation_job_id'))
            assign_value(maps.fetch(:child_workflow_ids_by_step_id), step_id, metadata_value(metadata, 'child_workflow_id'))
          end

          def decoded_metadata(step_row)
            payload = step_row[:metadata_payload]
            payload ? PayloadCodec.decode(payload) : {}
          end

          def metadata_value(metadata, key)
            metadata[key] || metadata[key.to_sym]
          end

          def assign_requirement(target, job_id, requirement)
            target[job_id] = normalized_requirement(requirement) if requirement
          end

          def assign_value(target, step_id, value)
            target[step_id] = value if value
          end

          def normalized_requirement(requirement)
            requirement.to_h.each_with_object({}) do |(key, value), normalized|
              normalized[key.to_sym] = value.is_a?(String) && key.to_s == 'kind' ? value.to_sym : value
            end.freeze
          end
        end
      end
    end
  end
end
