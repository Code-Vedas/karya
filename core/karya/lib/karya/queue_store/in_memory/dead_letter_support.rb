# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Dead-letter isolation, recovery, and inspection helpers.
      module DeadLetterSupport
        RETRY_EXHAUSTED_REASON = 'retry-policy-exhausted'
        CLASSIFICATION_ESCALATED_REASON = 'retry-policy-escalated'

        # Frozen skipped-job entry for a dead-letter mutation report.
        class SkippedJob
          def initialize(job_id:, reason:, state: nil)
            @job_id = job_id
            @reason = reason
            @state = state
          end

          def to_h
            { job_id:, reason:, state: }.freeze
          end

          private

          attr_reader :job_id, :reason, :state
        end

        # Iterates requested job ids and marks duplicate requests.
        class RequestedJobIds
          def initialize(job_ids)
            @job_ids = job_ids
            @seen_job_ids = {}
          end

          def each
            job_ids.each do |job_id|
              duplicate_request = seen_job_ids.key?(job_id)
              seen_job_ids[job_id] = true
              yield job_id, duplicate_request
            end
          end

          private

          attr_reader :job_ids, :seen_job_ids
        end

        # Snapshot entry for one isolated dead-letter job.
        class SnapshotEntry
          def initialize(job:)
            @job = job
          end

          def to_h
            {
              job_id: job.id,
              queue: job.queue,
              handler: job.handler,
              state: job.state,
              attempt: job.attempt,
              failure_classification: job.failure_classification,
              dead_letter_reason: job.dead_letter_reason,
              dead_lettered_at: job.dead_lettered_at,
              dead_letter_source_state: job.dead_letter_source_state,
              available_actions: %i[replay retry discard].freeze
            }.freeze
          end

          private

          attr_reader :job
        end

        private_constant :RequestedJobIds, :SkippedJob, :SnapshotEntry

        def dead_letter_jobs(job_ids:, now:, reason:)
          normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)
          normalized_job_ids = normalize_job_ids(job_ids)
          normalized_reason = Internal::DeadLetterReason.normalize(reason, error_class: InvalidQueueStoreOperationError)

          @mutex.synchronize do
            build_dead_letter_report(
              action: :dead_letter_jobs,
              job_ids: normalized_job_ids,
              now: normalized_now
            ) do |job_id, changed_jobs, skipped_jobs|
              dead_letter_requested_job(job_id, normalized_now, normalized_reason, changed_jobs, skipped_jobs)
            end
          end
        end

        def replay_dead_letter_jobs(job_ids:, now:)
          normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)
          normalized_job_ids = normalize_job_ids(job_ids)

          @mutex.synchronize do
            build_dead_letter_report(action: :replay_dead_letter_jobs, job_ids: normalized_job_ids, now: normalized_now) do |job_id, changed_jobs, skipped_jobs|
              replay_dead_letter_job(job_id, normalized_now, changed_jobs, skipped_jobs)
            end
          end
        end

        def retry_dead_letter_jobs(job_ids:, now:, next_retry_at:)
          normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)
          normalized_next_retry_at = normalize_time(:next_retry_at, next_retry_at, error_class: InvalidQueueStoreOperationError)
          normalized_job_ids = normalize_job_ids(job_ids)

          @mutex.synchronize do
            build_dead_letter_report(action: :retry_dead_letter_jobs, job_ids: normalized_job_ids, now: normalized_now) do |job_id, changed_jobs, skipped_jobs|
              retry_dead_letter_job(job_id, normalized_now, normalized_next_retry_at, changed_jobs, skipped_jobs)
            end
          end
        end

        def discard_dead_letter_jobs(job_ids:, now:)
          normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)
          normalized_job_ids = normalize_job_ids(job_ids)

          @mutex.synchronize do
            build_dead_letter_report(
              action: :discard_dead_letter_jobs,
              job_ids: normalized_job_ids,
              now: normalized_now
            ) do |job_id, changed_jobs, skipped_jobs|
              discard_dead_letter_job(job_id, normalized_now, changed_jobs, skipped_jobs)
            end
          end
        end

        def dead_letter_snapshot(now:)
          normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

          @mutex.synchronize do
            expire_reservations_locked(normalized_now)
            {
              captured_at: normalized_now.dup.freeze,
              dead_letters: snapshot_dead_letters
            }.freeze
          end
        end

        private

        def build_dead_letter_report(action:, job_ids:, now:)
          changed_jobs = []
          skipped_jobs = []
          RequestedJobIds.new(job_ids).each do |job_id, duplicate_request|
            if duplicate_request
              skipped_jobs << SkippedJob.new(job_id:, reason: :duplicate_request).to_h
            else
              yield job_id, changed_jobs, skipped_jobs
            end
          end
          BulkMutationReport.new(action:, performed_at: now, requested_job_ids: job_ids, changed_jobs:, skipped_jobs:)
        end

        def dead_letter_requested_job(job_id, now, reason, changed_jobs, skipped_jobs)
          job = state.jobs_by_id[job_id]
          return skipped_jobs << SkippedJob.new(job_id:, reason: :not_found).to_h unless job

          unless job.can_transition_to?(:dead_letter)
            skipped_jobs << SkippedJob.new(job_id:, reason: :ineligible_state, state: job.state).to_h
            return
          end

          cleanup_dead_letter_indexes(job)
          changed_jobs << store_job(job: dead_letter_job(job, now, reason))
        end

        def replay_dead_letter_job(job_id, now, changed_jobs, skipped_jobs)
          recover_dead_letter_job(job_id, :queued, now, nil, changed_jobs, skipped_jobs)
        end

        def retry_dead_letter_job(job_id, now, next_retry_at, changed_jobs, skipped_jobs)
          recover_dead_letter_job(job_id, :retry_pending, now, next_retry_at, changed_jobs, skipped_jobs)
        end

        def discard_dead_letter_job(job_id, now, changed_jobs, skipped_jobs)
          job = state.jobs_by_id[job_id]
          return skipped_jobs << SkippedJob.new(job_id:, reason: :not_found).to_h unless job

          state_name = job.state
          unless state_name == :dead_letter && job.can_transition_to?(:cancelled)
            skipped_jobs << SkippedJob.new(job_id:, reason: :ineligible_state, state: state_name).to_h
            return
          end

          changed_jobs << store_job(job: clear_dead_letter_metadata(job, :cancelled, now, nil))
        end

        def recover_dead_letter_job(job_id, next_state, now, next_retry_at, changed_jobs, skipped_jobs)
          job = state.jobs_by_id[job_id]
          return skipped_jobs << SkippedJob.new(job_id:, reason: :not_found).to_h unless job

          state_name = job.state
          unless state_name == :dead_letter && job.can_transition_to?(next_state)
            skipped_jobs << SkippedJob.new(job_id:, reason: :ineligible_state, state: state_name).to_h
            return
          end

          recovered_job = clear_dead_letter_metadata(job, next_state, now, next_retry_at)
          if uniqueness_conflict?(recovered_job, exclude_job_id: job_id, now:)
            skipped_jobs << SkippedJob.new(job_id:, reason: :uniqueness_conflict, state: state_name).to_h
            return
          end

          state.register_retry_pending(job_id) if next_state == :retry_pending
          changed_jobs << store_and_requeue_if_needed(recovered_job)
        end

        def dead_letter_job(job, now, reason)
          job.transition_to(
            :dead_letter,
            updated_at: now,
            next_retry_at: nil,
            failure_classification: job.failure_classification,
            dead_letter_reason: reason,
            dead_lettered_at: now,
            dead_letter_source_state: job.state
          )
        end

        def clear_dead_letter_metadata(job, next_state, now, next_retry_at)
          job.transition_to(
            next_state,
            updated_at: now,
            next_retry_at:,
            failure_classification: nil,
            dead_letter_reason: nil,
            dead_lettered_at: nil,
            dead_letter_source_state: nil
          )
        end

        def retry_escalation_reason(retry_decision)
          retry_decision.reason == :retry_exhausted ? RETRY_EXHAUSTED_REASON : CLASSIFICATION_ESCALATED_REASON
        end

        def cleanup_dead_letter_indexes(job)
          job_id = job.id
          case job.state
          when :queued
            delete_queued_job_id(job)
          when :retry_pending
            state.delete_retry_pending(job_id)
          when :reserved
            cancel_reservation_for(job_id)
          when :running
            cancel_execution_for(job_id)
          end
        end

        def snapshot_dead_letters
          state.jobs_by_id.each_value.filter_map do |job|
            SnapshotEntry.new(job:).to_h if job.state == :dead_letter
          end.freeze
        end
      end
    end
  end
end
