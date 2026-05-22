# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Immutable inspection view for one workflow batch at a point in time.
    class BatchSnapshot
      FAILED_STATES = %i[failed dead_letter].freeze
      COMPLETED_STATES = %i[succeeded cancelled].freeze

      attr_reader :aggregate_state,
                  :batch_id,
                  :captured_at,
                  :completed_count,
                  :failed_count,
                  :job_ids,
                  :jobs,
                  :state_counts,
                  :total_count

      def initialize(batch_id:, captured_at:, job_ids:, jobs:)
        @batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)
        @captured_at = Timestamp.new(:captured_at, captured_at).to_time
        @job_ids = JobIdList.new(job_ids).to_a
        @jobs = JobList.new(jobs).to_a
        validate_membership
        @jobs_by_id = @jobs.to_h { |job| [job.id, job] }.freeze
        summary = Summary.new(@jobs)
        @state_counts = summary.state_counts
        @total_count = @jobs.length
        @completed_count = summary.completed_count
        @failed_count = summary.failed_count
        @aggregate_state = AggregateState.new(@jobs).to_sym
        freeze
      end

      def include_job?(job_id)
        normalized_job_id = Workflow.send(:normalize_batch_identifier, :job_id, job_id)
        jobs_by_id.key?(normalized_job_id)
      end

      def job(job_id)
        normalized_job_id = Workflow.send(:normalize_batch_identifier, :job_id, job_id)
        jobs_by_id[normalized_job_id]
      end

      def fetch_job(job_id)
        normalized_job_id = Workflow.send(:normalize_batch_identifier, :job_id, job_id)
        jobs_by_id.fetch(normalized_job_id) do
          raise UnknownBatchError, "batch #{batch_id.inspect} does not include job #{normalized_job_id.inspect}"
        end
      end

      # Normalizes timestamps into immutable values.
      class Timestamp
        def initialize(name, value)
          @name = name
          @value = value
        end

        def to_time
          return value.dup.freeze if value.is_a?(Time)

          raise InvalidBatchError, "#{name} must be a Time"
        end

        private

        attr_reader :name, :value
      end

      # Normalizes snapshot job ids without interning request input.
      class JobIdList
        def initialize(job_ids)
          @job_ids = job_ids
        end

        def to_a
          raise InvalidBatchError, 'job_ids must be an Array' unless job_ids.is_a?(Array)
          raise InvalidBatchError, 'batch snapshot must include at least one job id' if job_ids.empty?

          normalized_job_ids = job_ids.map do |job_id|
            Workflow.send(:normalize_batch_identifier, :job_id, job_id)
          end
          duplicate_job_id = normalized_job_ids.tally.find { |_job_id, count| count > 1 }&.first
          raise InvalidBatchError, "duplicate batch job id #{duplicate_job_id.inspect}" if duplicate_job_id

          normalized_job_ids.freeze
        end

        private

        attr_reader :job_ids
      end

      # Normalizes a snapshot job list while preserving current job objects.
      class JobList
        def initialize(jobs)
          @jobs = jobs
        end

        def to_a
          raise InvalidBatchError, 'jobs must be an Array' unless jobs.is_a?(Array)
          raise InvalidBatchError, 'batch snapshot must include at least one job' if jobs.empty?

          jobs.each do |job|
            raise InvalidBatchError, 'jobs entries must be Karya::Job' unless job.is_a?(Job)
          end
          jobs.dup.freeze
        end

        private

        attr_reader :jobs
      end

      # Summarizes current member states for aggregate inspection.
      class Summary
        def initialize(jobs)
          @jobs = jobs
        end

        def state_counts
          @state_counts ||= jobs.each_with_object(Hash.new(0)) do |job, counts|
            counts[job.state] += 1
          end.freeze
        end

        def completed_count
          jobs.count { |job| COMPLETED_STATES.include?(job.state) }
        end

        def failed_count
          jobs.count { |job| FAILED_STATES.include?(job.state) }
        end

        private

        attr_reader :jobs
      end

      # Derives the aggregate state for the whole batch from member states.
      class AggregateState
        def initialize(jobs)
          @jobs = jobs
        end

        def to_sym
          return :failed if any_state?(FAILED_STATES)
          return :running if jobs.any? { |job| !job.terminal? }
          return :succeeded if only_state?(:succeeded)
          return :cancelled if only_state?(:cancelled)

          :completed
        end

        private

        attr_reader :jobs

        def any_state?(states)
          jobs.any? { |job| states.include?(job.state) }
        end

        def only_state?(state)
          jobs.all? { |job| job.state == state }
        end
      end

      private_constant :AggregateState, :COMPLETED_STATES, :FAILED_STATES, :JobIdList, :JobList, :Summary, :Timestamp

      private

      attr_reader :jobs_by_id

      def validate_membership
        snapshot_job_ids = jobs.map(&:id)
        return if snapshot_job_ids == job_ids

        raise InvalidBatchError, 'job_ids must match jobs in order'
      end
    end
  end
end
