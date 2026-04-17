# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Lease recovery helpers that requeue expired reservations and executions.
      module RecoverySupport
        private

        def requeue_reservation(reservation, now)
          reservation_token = reservation.token
          jobs_by_id = state.jobs_by_id
          state.reservations_by_token.delete(reservation_token)
          state.delete_reservation_token(reservation_token)

          reserved_job = jobs_by_id.fetch(reservation.job_id)
          resolve_reentry_and_store(
            reserved_job.transition_to(:queued, updated_at: now, failure_classification: nil),
            now:
          )
        end

        def requeue_expired_reservation(reservation, now)
          queued_job = requeue_reservation(reservation, now)
          state.mark_expired(reservation.token)
          queued_job
        end

        def requeue_expired_execution(reservation, now)
          reservation_token = reservation.token
          jobs_by_id = state.jobs_by_id
          state.executions_by_token.delete(reservation_token)
          state.delete_execution_token(reservation_token)

          running_job = jobs_by_id.fetch(reservation.job_id)
          queued_job = ExecutionRecovery.new(running_job, now).to_queued_job
          state.delete_retry_pending(queued_job.id)
          state.mark_expired(reservation_token)
          resolve_reentry_and_store(queued_job, now:)
        end
      end
    end
  end
end
