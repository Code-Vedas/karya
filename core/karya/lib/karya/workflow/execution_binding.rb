# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Normalized binding from workflow definition steps to concrete submission jobs.
    class ExecutionBinding
      attr_reader :batch_id, :compensation_jobs_by_step_id, :dependency_job_ids_by_job_id, :jobs

      def initialize(definition:, jobs_by_step_id:, batch_id:, compensation_jobs_by_step_id: {})
        @definition = validate_definition(definition)
        @batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)
        normalized_jobs = JobMap.new(jobs_by_step_id).to_h
        validate_step_coverage(normalized_jobs)
        @jobs_by_step_id = normalized_jobs
        validate_jobs
        @compensation_jobs_by_step_id = CompensationJobMap.new(
          definition: @definition,
          jobs_by_step_id: compensation_jobs_by_step_id
        ).to_h
        @jobs = @definition.steps.map { |workflow_step| normalized_jobs.fetch(workflow_step.id) }.freeze
        @dependency_job_ids_by_job_id = DependencyJobIds.new(definition: @definition, jobs_by_step_id: normalized_jobs).to_h
        freeze
      end

      private

      attr_reader :definition, :jobs_by_step_id

      def validate_definition(value)
        return value if value.is_a?(Definition)

        raise InvalidExecutionError, 'definition must be a Karya::Workflow::Definition'
      end

      def validate_step_coverage(normalized_jobs)
        expected_step_ids = definition.steps.map(&:id)
        actual_step_ids = normalized_jobs.keys
        missing_step_ids = expected_step_ids - actual_step_ids
        unknown_step_ids = actual_step_ids - expected_step_ids

        raise InvalidExecutionError, "missing workflow step job #{missing_step_ids.first.inspect}" unless missing_step_ids.empty?
        raise InvalidExecutionError, "unknown workflow step job #{unknown_step_ids.first.inspect}" unless unknown_step_ids.empty?
      end

      def validate_jobs
        definition.steps.each do |workflow_step|
          job = jobs_by_step_id.fetch(workflow_step.id)
          StepJob.new(workflow_step, job).validate
        end
      end

      # Normalizes caller-supplied step ids without interning request input.
      class JobMap
        def initialize(jobs_by_step_id, label: 'workflow step job')
          @jobs_by_step_id = jobs_by_step_id
          @label = label
        end

        def to_h
          raise InvalidExecutionError, 'jobs_by_step_id must be a Hash' unless jobs_by_step_id.is_a?(Hash)

          jobs_by_step_id.each_with_object({}) do |(step_id, job), normalized|
            normalized_step_id = Workflow.send(:normalize_execution_identifier, :step_id, step_id)
            raise InvalidExecutionError, "duplicate #{label} #{normalized_step_id.inspect}" if normalized.key?(normalized_step_id)

            normalized[normalized_step_id] = job
          end.freeze
        end

        private

        attr_reader :jobs_by_step_id, :label
      end

      # Validates one concrete job against its workflow step contract.
      class StepJob
        def initialize(workflow_step, job)
          @workflow_step = workflow_step
          @job = job
        end

        def validate
          raise InvalidExecutionError, "workflow step #{step_label} job must be a Karya::Job" unless job.is_a?(Job)
          raise InvalidExecutionError, "workflow step #{step_label} job must be in :submission state" unless job.state == :submission
          raise InvalidExecutionError, "workflow step #{step_label} job handler must match workflow step handler" unless job.handler == workflow_step.handler
          return if job.arguments == workflow_step.arguments

          raise InvalidExecutionError, "workflow step #{step_label} job arguments must match workflow step arguments"
        end

        private

        attr_reader :job, :workflow_step

        def step_label
          workflow_step.id.inspect
        end
      end

      # Normalizes and validates compensation job specs by workflow step id.
      class CompensationJobMap
        def initialize(definition:, jobs_by_step_id:)
          @definition = definition
          @jobs_by_step_id = jobs_by_step_id
        end

        def to_h
          raise InvalidExecutionError, 'compensation_jobs_by_step_id must be a Hash' unless jobs_by_step_id.is_a?(Hash)

          normalized_jobs = JobMap.new(jobs_by_step_id, label: 'workflow compensation job').to_h
          validate_step_coverage(normalized_jobs)
          validate_jobs(normalized_jobs)
          normalized_jobs.freeze
        end

        private

        attr_reader :definition, :jobs_by_step_id

        def validate_step_coverage(normalized_jobs)
          expected_step_ids = definition.steps.select(&:compensable?).map(&:id)
          actual_step_ids = normalized_jobs.keys
          missing_step_ids = expected_step_ids - actual_step_ids
          unknown_step_ids = actual_step_ids - expected_step_ids

          raise InvalidExecutionError, "missing workflow compensation job #{missing_step_ids.first.inspect}" unless missing_step_ids.empty?
          raise InvalidExecutionError, "unknown workflow compensation job #{unknown_step_ids.first.inspect}" unless unknown_step_ids.empty?
        end

        def validate_jobs(normalized_jobs)
          definition.steps.select(&:compensable?).each do |workflow_step|
            CompensationJob.new(workflow_step, normalized_jobs.fetch(workflow_step.id)).validate
          end
        end
      end

      # Validates one compensation job against its workflow step contract.
      class CompensationJob
        def initialize(workflow_step, job)
          @workflow_step = workflow_step
          @job = job
        end

        def validate
          raise InvalidExecutionError, "workflow compensation #{step_label} job must be a Karya::Job" unless job.is_a?(Job)
          raise InvalidExecutionError, "workflow compensation #{step_label} job must be in :submission state" unless job.state == :submission
          unless job.handler == workflow_step.compensate_with
            raise InvalidExecutionError, "workflow compensation #{step_label} job handler must match workflow compensation handler"
          end
          return if job.arguments == workflow_step.compensation_arguments

          raise InvalidExecutionError, "workflow compensation #{step_label} job arguments must match workflow compensation arguments"
        end

        private

        attr_reader :job, :workflow_step

        def step_label
          workflow_step.id.inspect
        end
      end

      # Maps each concrete workflow job id to its prerequisite concrete job ids.
      class DependencyJobIds
        def initialize(definition:, jobs_by_step_id:)
          @definition = definition
          @jobs_by_step_id = jobs_by_step_id
        end

        def to_h
          definition.steps.each_with_object({}) do |workflow_step, normalized|
            job = jobs_by_step_id.fetch(workflow_step.id)
            normalized[job.id] = dependency_job_ids(workflow_step)
          end.freeze
        end

        private

        attr_reader :definition, :jobs_by_step_id

        def dependency_job_ids(workflow_step)
          workflow_step.depends_on.map do |dependency_step_id|
            jobs_by_step_id.fetch(dependency_step_id).id
          end.freeze
        end
      end

      private_constant :CompensationJob,
                       :CompensationJobMap,
                       :DependencyJobIds,
                       :JobMap,
                       :StepJob
    end
  end
end
