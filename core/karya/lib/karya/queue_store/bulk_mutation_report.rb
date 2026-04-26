# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    # Immutable result for one bounded bulk queue-store mutation.
    class BulkMutationReport
      ACTIONS = %i[
        enqueue_many
        retry_jobs
        cancel_jobs
        dead_letter_jobs
        replay_dead_letter_jobs
        retry_dead_letter_jobs
        discard_dead_letter_jobs
        enqueue_child_workflow
        rollback_workflow
        sync_child_workflows
        retry_workflow_steps
        dead_letter_workflow_steps
        replay_workflow_steps
        retry_dead_letter_workflow_steps
        discard_workflow_steps
      ].freeze
      SKIPPED_JOB_REASONS = %i[not_found ineligible_state duplicate_request uniqueness_conflict].freeze

      attr_reader :action, :changed_jobs, :performed_at, :requested_count, :requested_job_ids, :skipped_jobs

      # Validates and freezes a string job-id array.
      class JobIdList
        def initialize(name, job_ids)
          @name = name
          @job_ids = job_ids
        end

        def to_a
          raise InvalidQueueStoreOperationError, "#{name} must be an Array" unless job_ids.is_a?(Array)

          job_ids.map do |job_id|
            raise InvalidQueueStoreOperationError, "#{name} entries must be Strings" unless job_id.is_a?(String)

            job_id.dup.freeze
          end.freeze
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
        raise InvalidQueueStoreOperationError, action_error_message unless ACTIONS.include?(action)
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

        job_id = skipped_job.fetch(:job_id)
        reason = skipped_job.fetch(:reason)
        state = skipped_job.fetch(:state, nil)
        raise InvalidQueueStoreOperationError, 'skipped job_id must be a String' unless job_id.is_a?(String)
        raise InvalidQueueStoreOperationError, skipped_reason_error_message unless SKIPPED_JOB_REASONS.include?(reason)

        {
          job_id: job_id.dup.freeze,
          reason:,
          state: normalize_skipped_state(state)
        }.freeze
      end

      def normalize_skipped_state(state)
        case state
        when NilClass, Symbol
          state
        when String
          state.dup.freeze
        else
          raise InvalidQueueStoreOperationError, 'skipped state must be a String, Symbol, or nil'
        end
      end

      def skipped_reason_error_message
        'skipped reason must be one of :not_found, :ineligible_state, :duplicate_request, or :uniqueness_conflict'
      end

      def action_error_message
        'action must be one of :enqueue_many, :retry_jobs, :cancel_jobs, :dead_letter_jobs, ' \
          ':replay_dead_letter_jobs, :retry_dead_letter_jobs, :discard_dead_letter_jobs, :enqueue_child_workflow, :rollback_workflow, ' \
          ':retry_workflow_steps, :dead_letter_workflow_steps, :replay_workflow_steps, ' \
          ':retry_dead_letter_workflow_steps, :discard_workflow_steps, or :sync_child_workflows'
      end

      private_constant :ACTIONS, :JobIdList, :JobList, :SKIPPED_JOB_REASONS
    end
  end
end
