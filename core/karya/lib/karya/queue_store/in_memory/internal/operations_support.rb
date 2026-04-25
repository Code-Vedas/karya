# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Bounded bulk mutation and queue-control operations.
        module OperationsSupport
          # Builds a uniqueness-shaped rejection for duplicates inside one batch.
          class BatchDuplicateDecision
            def initialize(job:, now:)
              @job = job
              @now = now
            end

            def for(accepted_job:, uniqueness_conflict:)
              @conflicting_job = accepted_job
              return job_id if accepted_job.id == job.id

              idempotency_key = job.idempotency_key
              return idempotency_key_decision if idempotency_key && accepted_job.idempotency_key == idempotency_key
              return uniqueness_key if uniqueness_conflict

              nil
            end

            private

            attr_reader :conflicting_job, :job, :now

            def job_id
              to_h(result: :duplicate_job_id, key_type: :job_id, key: job.id)
            end

            def idempotency_key_decision
              to_h(result: :duplicate_idempotency_key, key_type: :idempotency_key, key: job.idempotency_key)
            end

            def uniqueness_key
              to_h(result: :duplicate_uniqueness_key, key_type: :uniqueness_key, key: job.uniqueness_key)
            end

            def to_h(result:, key_type:, key:)
              {
                captured_at: now.dup.freeze,
                job_id: job.id,
                action: :reject,
                result:,
                key_type:,
                key:,
                conflicting_job_id: conflicting_job.id,
                uniqueness_scope: job.uniqueness_scope
              }.freeze
            end
          end

          # Builds a queued job for an operator-forced retry when the lifecycle allows it.
          class RetryCandidate
            def initialize(job:, now:)
              @job = job
              @now = now
            end

            def to_job
              case job.state
              when :failed
                failed_job_retry
              when :retry_pending
                retry_pending_job_retry
              end
            end

            private

            attr_reader :job, :now

            def failed_job_retry
              job.transition_to(:retry_pending, updated_at: now, next_retry_at: now).transition_to(
                :queued,
                updated_at: now,
                next_retry_at: nil,
                failure_classification: nil
              )
            end

            def retry_pending_job_retry
              job.transition_to(:queued, updated_at: now, next_retry_at: nil, failure_classification: nil)
            end
          end

          private_constant :BatchDuplicateDecision, :RetryCandidate

          def enqueue_many(jobs:, now:, batch_id: nil)
            normalized_now = normalize_time(:now, now, error_class: InvalidEnqueueError)

            @mutex.synchronize do
              validated_jobs = validate_bulk_enqueue_jobs(jobs)
              batch = build_optional_enqueue_batch(batch_id:, jobs: validated_jobs, now: normalized_now)
              validate_bulk_enqueue_uniqueness(validated_jobs, normalized_now)
              expire_reservations_locked(normalized_now)
              queued_jobs = validated_jobs.map { |job| enqueue_validated_job(job, normalized_now) }
              store_optional_batch(batch)
              BulkMutationReport.new(
                action: :enqueue_many,
                performed_at: normalized_now,
                requested_job_ids: validated_jobs.map(&:id),
                changed_jobs: queued_jobs,
                skipped_jobs: []
              )
            end
          end

          def retry_jobs(job_ids:, now:)
            normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)
            normalized_job_ids = normalize_job_ids(job_ids)

            @mutex.synchronize do
              Karya::Internal::BulkMutation::ReportBuilder.new(
                action: :retry_jobs,
                job_ids: normalized_job_ids,
                now: normalized_now
              ).to_report do |job_id, changed_jobs, skipped_jobs|
                retry_requested_job(job_id, normalized_now, changed_jobs, skipped_jobs)
              end
            end
          end

          def cancel_jobs(job_ids:, now:)
            normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)
            normalized_job_ids = normalize_job_ids(job_ids)

            @mutex.synchronize do
              Karya::Internal::BulkMutation::ReportBuilder.new(
                action: :cancel_jobs,
                job_ids: normalized_job_ids,
                now: normalized_now
              ).to_report do |job_id, changed_jobs, skipped_jobs|
                cancel_requested_job(job_id, normalized_now, changed_jobs, skipped_jobs)
              end
            end
          end

          def pause_queue(queue:, now:)
            normalized_queue = normalize_identifier(:queue, queue, error_class: InvalidQueueStoreOperationError)
            normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

            @mutex.synchronize do
              changed = state.mark_queue_paused(normalized_queue, normalized_now) == :changed
              QueueControlResult.new(action: :pause_queue, performed_at: normalized_now, queue: normalized_queue, paused: true, changed:)
            end
          end

          def resume_queue(queue:, now:)
            normalized_queue = normalize_identifier(:queue, queue, error_class: InvalidQueueStoreOperationError)
            normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

            @mutex.synchronize do
              changed = state.unmark_queue_paused(normalized_queue) == :changed
              QueueControlResult.new(action: :resume_queue, performed_at: normalized_now, queue: normalized_queue, paused: false, changed:)
            end
          end

          private

          def validate_bulk_enqueue_jobs(jobs)
            raise InvalidEnqueueError, 'jobs must be an Array' unless jobs.is_a?(Array)

            jobs.dup.each { |job| validate_enqueue(job) }
          end

          def validate_bulk_enqueue_uniqueness(jobs, now)
            accepted_jobs = []
            jobs.each do |job|
              duplicate_decision = build_uniqueness_decision(job, now)
              raise_duplicate_enqueue_error(duplicate_decision) if duplicate_decision.fetch(:action) == :reject

              batch_duplicate = duplicate_batch_decision(job, accepted_jobs, now)
              raise_duplicate_enqueue_error(batch_duplicate) if batch_duplicate

              accepted_jobs << job.transition_to(:queued, updated_at: now)
            end
          end

          def duplicate_batch_decision(job, accepted_jobs, now)
            decision = BatchDuplicateDecision.new(job:, now:)
            accepted_jobs.each do |accepted_job|
              duplicate_decision = decision.for(
                accepted_job:,
                uniqueness_conflict: duplicate_uniqueness_key?(job, accepted_job)
              )
              return duplicate_decision if duplicate_decision
            end

            nil
          end

          def duplicate_uniqueness_key?(job, accepted_job)
            uniqueness_key = job.uniqueness_key
            return false unless uniqueness_key
            return false unless accepted_job.uniqueness_key == uniqueness_key

            uniqueness_conflict_between?(accepted_job, job)
          end

          def enqueue_validated_job(job, now)
            queued_job = job.transition_to(:queued, updated_at: now)
            state.queue_job_ids_for(queued_job.queue) << queued_job.id
            store_job(job: queued_job)
          end

          def normalize_job_ids(job_ids)
            raise InvalidQueueStoreOperationError, 'job_ids must be an Array' unless job_ids.is_a?(Array)

            job_ids.map do |job_id|
              normalize_identifier(:job_id, job_id, error_class: InvalidQueueStoreOperationError)
            end
          end

          def retry_requested_job(job_id, now, changed_jobs, skipped_jobs)
            job = state.jobs_by_id[job_id]
            unless job
              skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :not_found).to_h
              return
            end

            state_name = job.state
            retried_job = RetryCandidate.new(job:, now:).to_job
            unless retried_job
              skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :ineligible_state, state: state_name).to_h
              return
            end

            if uniqueness_conflict?(retried_job, exclude_job_id: job_id, now:)
              skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :uniqueness_conflict, state: state_name).to_h
              return
            end

            state.delete_retry_pending(job_id)
            changed_jobs << store_and_requeue_if_needed(retried_job)
          end

          def cancel_requested_job(job_id, now, changed_jobs, skipped_jobs)
            job = state.jobs_by_id[job_id]
            unless job
              skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :not_found).to_h
              return
            end

            unless job.can_transition_to?(:cancelled)
              skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :ineligible_state, state: job.state).to_h
              return
            end

            cleanup_cancelled_job_indexes(job)
            cancelled_job = job.transition_to(:cancelled, updated_at: now, next_retry_at: nil, failure_classification: nil)
            changed_jobs << store_job(job: cancelled_job)
          end

          def cleanup_cancelled_job_indexes(job)
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

          def delete_queued_job_id(job)
            queue = job.queue
            queue_job_ids = state.queued_job_ids_by_queue[queue]
            return unless queue_job_ids

            queue_job_ids.delete(job.id)
            state.delete_queue(queue) if queue_job_ids.empty?
          end

          def cancel_reservation_for(job_id)
            reservation_token = state.reservation_token_for_job(job_id)
            return unless reservation_token

            state.delete_reservation_token(reservation_token)
            state.mark_expired(reservation_token)
          end

          def cancel_execution_for(job_id)
            reservation_token = state.execution_token_for_job(job_id)
            return unless reservation_token

            state.delete_execution_token(reservation_token)
            state.mark_expired(reservation_token)
          end
        end
      end
    end
  end
end
