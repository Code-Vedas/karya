# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Immutable inspection view for one workflow step at a point in time.
    class StepSnapshot
      WAITING_STATES = %i[queued submission].freeze

      attr_reader :batch_id,
                  :job,
                  :job_id,
                  :prerequisite_job_ids,
                  :prerequisite_states,
                  :state,
                  :step_id,
                  :workflow_id

      def initialize(**attributes)
        attributes = Attributes.new(attributes)
        @workflow_id = attributes.workflow_id
        @batch_id = attributes.batch_id
        @step_id = attributes.step_id
        @job_id = attributes.job_id
        @job = attributes.job
        @state = @job.state
        @prerequisite_job_ids = attributes.prerequisite_job_ids
        @prerequisite_states = PrerequisiteStates.new(
          prerequisite_job_ids: @prerequisite_job_ids,
          prerequisite_states: attributes.prerequisite_states
        ).to_h
        freeze
      end

      def ready?
        waiting? && prerequisite_job_ids.all? { |prerequisite_job_id| prerequisite_states.fetch(prerequisite_job_id) == :succeeded }
      end

      def blocked?
        waiting? && !ready?
      end

      def active?
        !terminal? && !waiting?
      end

      def terminal?
        job.terminal?
      end

      # Validates and exposes step snapshot construction attributes.
      class Attributes
        REQUIRED_ATTRIBUTES = %i[
          workflow_id
          batch_id
          step_id
          job_id
          job
          prerequisite_job_ids
          prerequisite_states
        ].freeze

        def initialize(attributes)
          @attributes = attributes
          validate_keys
        end

        def workflow_id
          Workflow.send(:normalize_identifier, :workflow_id, fetch(:workflow_id))
        end

        def batch_id
          Workflow.send(:normalize_batch_identifier, :batch_id, fetch(:batch_id))
        end

        def step_id
          Workflow.send(:normalize_execution_identifier, :step_id, fetch(:step_id))
        end

        def job_id
          Workflow.send(:normalize_execution_identifier, :job_id, fetch(:job_id))
        end

        def job
          JobEntry.new(job_id:, job: fetch(:job)).to_job
        end

        def prerequisite_job_ids
          JobIdList.new(:prerequisite_job_id, fetch(:prerequisite_job_ids)).to_a
        end

        def prerequisite_states
          fetch(:prerequisite_states)
        end

        private

        attr_reader :attributes

        def fetch(name)
          attributes.fetch(name) { raise ArgumentError, "missing keyword: :#{name}" }
        end

        def validate_keys
          unknown_keys = attributes.keys - REQUIRED_ATTRIBUTES
          return if unknown_keys.empty?

          raise ArgumentError, "unknown keyword: :#{unknown_keys.first}"
        end
      end

      # Validates the concrete job backing a step snapshot.
      class JobEntry
        def initialize(job_id:, job:)
          @job_id = job_id
          @job = job
        end

        def to_job
          raise InvalidExecutionError, 'job must be Karya::Job' unless job.is_a?(Job)
          return job if job.id == job_id

          raise InvalidExecutionError, 'job_id must match job id'
        end

        private

        attr_reader :job, :job_id
      end

      # Normalizes ordered job id lists.
      class JobIdList
        def initialize(field_name, job_ids)
          @field_name = field_name
          @job_ids = job_ids
        end

        def to_a
          raise InvalidExecutionError, "#{field_name}s must be an Array" unless job_ids.is_a?(Array)

          normalized_job_ids = job_ids.map do |job_id|
            Workflow.send(:normalize_execution_identifier, field_name, job_id)
          end
          duplicate_job_id = normalized_job_ids.tally.find { |_job_id, count| count > 1 }&.first
          raise InvalidExecutionError, "duplicate #{field_name} #{duplicate_job_id.inspect}" if duplicate_job_id

          normalized_job_ids.freeze
        end

        private

        attr_reader :field_name, :job_ids
      end

      # Normalizes prerequisite states keyed by prerequisite job id.
      class PrerequisiteStates
        def initialize(prerequisite_job_ids:, prerequisite_states:)
          @prerequisite_job_ids = prerequisite_job_ids
          @prerequisite_states = prerequisite_states
        end

        def to_h
          raise InvalidExecutionError, 'prerequisite_states must be a Hash' unless prerequisite_states.is_a?(Hash)

          normalized_states = prerequisite_states.each_with_object({}) do |(job_id, state), states|
            normalized_job_id = Workflow.send(:normalize_execution_identifier, :prerequisite_job_id, job_id)
            states[normalized_job_id] = state
          end
          validate_membership(normalized_states)
          prerequisite_job_ids.to_h { |job_id| [job_id, normalized_states[job_id]] }.freeze
        end

        private

        attr_reader :prerequisite_job_ids, :prerequisite_states

        def validate_membership(normalized_states)
          unknown_job_id = normalized_states.keys.find { |job_id| !prerequisite_job_ids.include?(job_id) }
          return unless unknown_job_id

          raise InvalidExecutionError, "unknown prerequisite job #{unknown_job_id.inspect}"
        end
      end

      private_constant :Attributes, :JobEntry, :JobIdList, :PrerequisiteStates, :WAITING_STATES

      private

      def waiting?
        WAITING_STATES.include?(state)
      end
    end
  end
end
