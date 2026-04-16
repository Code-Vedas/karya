# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Retry policy helpers used during execution finalization and reserve maintenance.
      module RetrySupport
        private

        def promote_due_retry_pending_jobs(now)
          jobs_by_id = state.jobs_by_id

          state.retry_pending_job_ids.dup.each do |job_id|
            retry_pending_job = jobs_by_id.fetch(job_id)
            next_retry_at = retry_pending_job.next_retry_at
            next unless next_retry_at && next_retry_at <= now

            queued_job = retry_pending_job.transition_to(
              :queued,
              updated_at: now,
              next_retry_at: nil,
              failure_classification: nil
            )
            store_job(job: queued_job)
            state.queue_job_ids_for(queued_job.queue) << job_id
            state.delete_retry_pending(job_id)
          end
        end

        def retry_pending_job(running_job, now, retry_policy, failure_classification)
          failed_job = running_job.transition_to(
            :failed,
            updated_at: now,
            next_retry_at: nil,
            failure_classification:
          )
          next_retry_at = now + retry_policy.delay_for(failed_job.attempt)
          retry_pending_job = failed_job.transition_to(
            :retry_pending,
            updated_at: now,
            next_retry_at: next_retry_at,
            retry_policy:,
            failure_classification:
          )
          state.register_retry_pending(retry_pending_job.id)
          retry_pending_job
        end
      end
    end
  end
end
