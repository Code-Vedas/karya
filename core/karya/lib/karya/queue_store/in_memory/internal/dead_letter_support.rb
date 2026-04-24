# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Dead-letter isolation, recovery, and inspection helpers.
        module DeadLetterSupport
          AVAILABLE_ACTIONS = %i[replay retry discard].freeze
          RETRY_EXHAUSTED_REASON = 'retry-policy-exhausted'
          CLASSIFICATION_ESCALATED_REASON = 'retry-policy-escalated'

          # Builds dead-letter lifecycle transitions while keeping metadata rules in one place.
          class JobTransition
            def initialize(job:, now:)
              @job = job
              @now = now
            end

            def dead_letter(reason)
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

            def clear_dead_letter_metadata(next_state:, next_retry_at:)
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

            private

            attr_reader :job, :now
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
                available_actions: AVAILABLE_ACTIONS
              }.freeze
            end

            private

            attr_reader :job
          end

          private_constant :JobTransition, :SnapshotEntry

          def dead_letter_jobs(job_ids:, now:, reason:)
            normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)
            normalized_job_ids = normalize_job_ids(job_ids)
            normalized_reason = Karya::Internal::DeadLetterReason.normalize(reason, error_class: InvalidQueueStoreOperationError)

            @mutex.synchronize do
              Karya::Internal::BulkMutation::ReportBuilder.new(
                action: :dead_letter_jobs,
                job_ids: normalized_job_ids,
                now: normalized_now
              ).to_report do |job_id, changed_jobs, skipped_jobs|
                dead_letter_requested_job(job_id, normalized_now, normalized_reason, changed_jobs, skipped_jobs)
              end
            end
          end

          def replay_dead_letter_jobs(job_ids:, now:)
            normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)
            normalized_job_ids = normalize_job_ids(job_ids)

            @mutex.synchronize do
              Karya::Internal::BulkMutation::ReportBuilder.new(
                action: :replay_dead_letter_jobs,
                job_ids: normalized_job_ids,
                now: normalized_now
              ).to_report do |job_id, changed_jobs, skipped_jobs|
                replay_dead_letter_job(job_id, normalized_now, changed_jobs, skipped_jobs)
              end
            end
          end

          def retry_dead_letter_jobs(job_ids:, now:, next_retry_at:)
            normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)
            normalized_next_retry_at = normalize_time(:next_retry_at, next_retry_at, error_class: InvalidQueueStoreOperationError)
            normalized_job_ids = normalize_job_ids(job_ids)

            @mutex.synchronize do
              Karya::Internal::BulkMutation::ReportBuilder.new(
                action: :retry_dead_letter_jobs,
                job_ids: normalized_job_ids,
                now: normalized_now
              ).to_report do |job_id, changed_jobs, skipped_jobs|
                retry_dead_letter_job(job_id, normalized_now, normalized_next_retry_at, changed_jobs, skipped_jobs)
              end
            end
          end

          def discard_dead_letter_jobs(job_ids:, now:)
            normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)
            normalized_job_ids = normalize_job_ids(job_ids)

            @mutex.synchronize do
              Karya::Internal::BulkMutation::ReportBuilder.new(
                action: :discard_dead_letter_jobs,
                job_ids: normalized_job_ids,
                now: normalized_now
              ).to_report do |job_id, changed_jobs, skipped_jobs|
                discard_dead_letter_job(job_id, normalized_now, changed_jobs, skipped_jobs)
              end
            end
          end

          def dead_letter_snapshot(now:)
            normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

            @mutex.synchronize do
              prepare_dead_letter_snapshot(normalized_now)
              {
                captured_at: normalized_now.dup.freeze,
                dead_letters: snapshot_dead_letters
              }.freeze
            end
          end

          private

          def prepare_dead_letter_snapshot(now)
            expired_reservations = collect_expired_leases(state.reservations_by_token, state.reservation_tokens_in_order, now)
            expired_executions = collect_expired_leases(state.executions_by_token, state.execution_tokens_in_order, now)
            expired_reservations.each { |reservation| requeue_expired_reservation(reservation, now) }
            expired_executions.each { |reservation| requeue_expired_execution(reservation, now) }
            nil
          end

          def dead_letter_requested_job(job_id, now, reason, changed_jobs, skipped_jobs)
            job = state.jobs_by_id[job_id]
            return skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :not_found).to_h unless job

            unless job.can_transition_to?(:dead_letter)
              skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :ineligible_state, state: job.state).to_h
              return
            end

            cleanup_dead_letter_indexes(job)
            changed_jobs << store_job(job: JobTransition.new(job:, now:).dead_letter(reason))
          end

          def replay_dead_letter_job(job_id, now, changed_jobs, skipped_jobs)
            recover_dead_letter_job(job_id, :queued, now, nil, changed_jobs, skipped_jobs)
          end

          def retry_dead_letter_job(job_id, now, next_retry_at, changed_jobs, skipped_jobs)
            recover_dead_letter_job(job_id, :retry_pending, now, next_retry_at, changed_jobs, skipped_jobs)
          end

          def discard_dead_letter_job(job_id, now, changed_jobs, skipped_jobs)
            job = state.jobs_by_id[job_id]
            return skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :not_found).to_h unless job

            state_name = job.state
            unless state_name == :dead_letter && job.can_transition_to?(:cancelled)
              skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :ineligible_state, state: state_name).to_h
              return
            end

            changed_jobs << store_job(
              job: JobTransition.new(job:, now:).clear_dead_letter_metadata(next_state: :cancelled, next_retry_at: nil)
            )
          end

          def recover_dead_letter_job(job_id, next_state, now, next_retry_at, changed_jobs, skipped_jobs)
            job = state.jobs_by_id[job_id]
            return skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :not_found).to_h unless job

            state_name = job.state
            unless state_name == :dead_letter && job.can_transition_to?(next_state)
              skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :ineligible_state, state: state_name).to_h
              return
            end

            recovered_job = JobTransition.new(job:, now:).clear_dead_letter_metadata(next_state:, next_retry_at:)
            if uniqueness_conflict?(recovered_job, exclude_job_id: job_id, now:)
              skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :uniqueness_conflict, state: state_name).to_h
              return
            end

            state.register_retry_pending(job_id) if next_state == :retry_pending
            changed_jobs << store_and_requeue_if_needed(recovered_job)
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
end
