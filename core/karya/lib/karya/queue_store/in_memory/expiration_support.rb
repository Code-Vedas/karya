# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Expiration helpers for queued, retry-pending, and reserved jobs.
      module ExpirationSupport
        private

        def expire_jobs_locked(now)
          expired_jobs = []
          expire_queued_jobs(now, expired_jobs)
          expire_retry_pending_jobs(now, expired_jobs)
          expired_jobs
        end

        def expire_queued_jobs(now, expired_jobs)
          queued_job_ids_by_queue = state.queued_job_ids_by_queue
          queued_job_ids_by_queue.each_value do |queue_job_ids|
            queue_job_ids.delete_if do |job_id|
              expire_queued_job?(job_id, now, expired_jobs)
            end
          end
          queued_job_ids_by_queue.delete_if { |_queue, queue_job_ids| queue_job_ids.empty? }
        end

        def expire_retry_pending_jobs(now, expired_jobs)
          jobs_by_id = state.jobs_by_id
          state.retry_pending_job_ids.dup.each do |job_id|
            job = jobs_by_id.fetch(job_id)
            next unless job_expired?(job, now)

            expired_retry_job = expired_job(job, now)
            jobs_by_id[job_id] = expired_retry_job
            state.delete_retry_pending(job_id)
            expired_jobs << expired_retry_job
          end
        end

        def expire_reserved_job(reservation, reserved_job, now)
          reservation_token = reservation.token
          state.reservations_by_token.delete(reservation_token)
          state.delete_reservation_token(reservation_token)
          state.mark_expired(reservation_token)

          failed_job = expired_job(reserved_job, now)
          state.jobs_by_id[failed_job.id] = failed_job
          failed_job
        end

        def expire_queued_job?(job_id, now, expired_jobs)
          jobs_by_id = state.jobs_by_id
          job = jobs_by_id.fetch(job_id)
          return false unless job_expired?(job, now)

          expired_queued_job = expired_job(job, now)
          jobs_by_id[job_id] = expired_queued_job
          expired_jobs << expired_queued_job
          true
        end

        def job_expired?(job, now)
          expires_at = job.expires_at
          expires_at && expires_at <= now
        end

        def expired_job(job, now)
          build_expired_job(job, now)
        end

        def build_expired_job(job, now)
          Job.new(
            id: job.id,
            queue: job.queue,
            handler: job.handler,
            arguments: job.arguments,
            priority: job.priority,
            concurrency_key: job.concurrency_key,
            rate_limit_key: job.rate_limit_key,
            retry_policy: job.retry_policy,
            execution_timeout: job.execution_timeout,
            expires_at: job.expires_at,
            lifecycle: job.send(:lifecycle),
            state: :failed,
            attempt: job.attempt,
            created_at: job.created_at,
            updated_at: now,
            next_retry_at: nil,
            failure_classification: :expired
          )
        end
      end
    end
  end
end
