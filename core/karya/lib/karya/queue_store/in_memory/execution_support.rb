# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Execution finalization and active lease helpers.
      module ExecutionSupport
        private

        def finalize_execution(reservation_token:, now:, next_state:, retry_policy: nil, failure_classification: nil)
          normalized_token = normalize_identifier(:reservation_token, reservation_token, error_class: InvalidQueueStoreOperationError)
          normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)
          normalized_retry_policy = Internal::RetryPolicyNormalizer.new(retry_policy, error_class: InvalidQueueStoreOperationError).normalize
          normalized_failure_classification = nil
          if next_state == :failed
            normalized_failure_classification = Internal::FailureClassification.normalize(
              failure_classification,
              error_class: InvalidQueueStoreOperationError
            )
          end

          @mutex.synchronize do
            executions_by_token = state.executions_by_token
            reservation = executions_by_token[normalized_token]
            reservation_label = normalized_token.inspect

            unless reservation
              raise_expired_reservation_error(normalized_token, reservation_label)
              raise UnknownReservationError, "reservation #{reservation_label} was not found"
            end

            if reservation.expired?(normalized_now)
              requeue_expired_execution(reservation, normalized_now)
              raise ExpiredReservationError, "reservation #{reservation_label} has expired"
            end

            finalized_job = finalized_execution_job(
              running_job: state.jobs_by_id.fetch(reservation.job_id),
              next_state:,
              now: normalized_now,
              retry_policy: normalized_retry_policy,
              failure_classification: normalized_failure_classification
            )
            state.jobs_by_id[finalized_job.id] = finalized_job
            executions_by_token.delete(normalized_token)
            state.delete_execution_token(normalized_token)
            finalized_job
          end
        end

        def finalized_execution_job(running_job:, next_state:, now:, retry_policy:, failure_classification:)
          failed_execution = next_state == :failed
          if failed_execution && failure_classification != :expired && retry_policy&.retry?(running_job.attempt)
            return retry_pending_job(running_job, now, retry_policy, failure_classification)
          end

          running_job.transition_to(
            next_state,
            updated_at: now,
            next_retry_at: nil,
            failure_classification: failed_execution ? failure_classification : nil
          )
        end

        def fetch_active_reservation(reservation_token, now)
          reservation = state.reservations_by_token[reservation_token]
          reservation_label = reservation_token.inspect

          unless reservation
            raise_expired_reservation_error(reservation_token, reservation_label)
            raise UnknownReservationError, "reservation #{reservation_label} was not found"
          end

          if reservation.expired?(now)
            requeue_expired_reservation(reservation, now)
            raise ExpiredReservationError, "reservation #{reservation_label} has expired"
          end

          reservation
        end

        def collect_expired_leases(leases_by_token, tokens_in_order, now, worker_id: nil)
          tokens_in_order.filter_map do |token|
            reservation = leases_by_token.fetch(token)
            reservation if reservation.expired?(now) && (!worker_id || reservation.worker_id == worker_id)
          end
        end
      end
    end
  end
end
