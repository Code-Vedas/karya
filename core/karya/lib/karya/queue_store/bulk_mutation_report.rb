# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    # Immutable result for one bounded bulk queue-store mutation.
    class BulkMutationReport
      attr_reader :action, :changed_jobs, :performed_at, :requested_count, :requested_job_ids, :skipped_jobs

      # Validates and freezes a string job-id array.
      class JobIdList
        def initialize(name, job_ids)
          @name = name
          @job_ids = job_ids
        end

        def to_a
          raise InvalidQueueStoreOperationError, "#{name} must be an Array" unless job_ids.is_a?(Array)

          job_ids.each do |job_id|
            raise InvalidQueueStoreOperationError, "#{name} entries must be Strings" unless job_id.is_a?(String)
          end
          job_ids.dup.freeze
        end

        private

        attr_reader :job_ids, :name
      end

      # Validates and freezes a job array.
      class JobList
        def initialize(name, jobs)
          @name = name
          @jobs = jobs
        end

        def to_a
          raise InvalidQueueStoreOperationError, "#{name} must be an Array" unless jobs.is_a?(Array)

          jobs.each do |job|
            raise InvalidQueueStoreOperationError, "#{name} entries must be Karya::Job" unless job.is_a?(Job)
          end
          jobs.dup.freeze
        end

        private

        attr_reader :jobs, :name
      end

      def initialize(action:, performed_at:, requested_job_ids:, changed_jobs:, skipped_jobs:)
        raise InvalidQueueStoreOperationError, 'action must be a Symbol' unless action.is_a?(Symbol)
        raise InvalidQueueStoreOperationError, 'performed_at must be a Time' unless performed_at.is_a?(Time)

        @action = action
        @performed_at = performed_at.dup.freeze
        @requested_job_ids = JobIdList.new(:requested_job_ids, requested_job_ids).to_a
        @changed_jobs = JobList.new(:changed_jobs, changed_jobs).to_a
        @skipped_jobs = normalize_skipped_jobs(skipped_jobs)
        @requested_count = @requested_job_ids.length

        freeze
      end

      private

      def normalize_skipped_jobs(skipped_jobs)
        raise InvalidQueueStoreOperationError, 'skipped_jobs must be an Array' unless skipped_jobs.is_a?(Array)

        skipped_jobs.map do |skipped_job|
          normalize_skipped_job(skipped_job)
        end.freeze
      end

      def normalize_skipped_job(skipped_job)
        raise InvalidQueueStoreOperationError, 'skipped_jobs entries must be Hashes' unless skipped_job.is_a?(Hash)

        normalized = skipped_job.dup
        job_id = normalized.fetch(:job_id)
        reason = normalized.fetch(:reason)
        raise InvalidQueueStoreOperationError, 'skipped job_id must be a String' unless job_id.is_a?(String)
        raise InvalidQueueStoreOperationError, 'skipped reason must be a Symbol' unless reason.is_a?(Symbol)

        normalized.freeze
      end

      private_constant :JobIdList, :JobList
    end
  end
end
