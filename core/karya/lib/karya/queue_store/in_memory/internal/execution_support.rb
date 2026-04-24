# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Execution finalization and active lease helpers.
        module ExecutionSupport
          private

          def finalize_execution(reservation_token:, now:, next_state:, retry_policy: nil, failure_classification: nil)
            normalized_token = normalize_identifier(:reservation_token, reservation_token, error_class: InvalidQueueStoreOperationError)
            normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)
            normalized_retry_policy = Karya::Internal::RetryPolicyNormalizer.new(retry_policy, error_class: InvalidQueueStoreOperationError).normalize
            normalized_failure_classification = nil
            if next_state == :failed
              normalized_failure_classification = Karya::Internal::FailureClassification.normalize(
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

              running_job = state.jobs_by_id.fetch(reservation.job_id)
              finalized_job = finalized_execution_job(
                running_job:,
                next_state:,
                now: normalized_now,
                retry_policy: normalized_retry_policy,
                failure_classification: normalized_failure_classification
              )
              persist_finalized_execution(
                finalized_job:,
                normalized_token:
              )
              if next_state == :succeeded
                record_execution_success(running_job, normalized_now)
              else
                record_execution_failure(running_job, normalized_failure_classification, normalized_now)
              end
              finalized_job
            end
          end

          def persist_finalized_execution(finalized_job:, normalized_token:)
            store_job(job: finalized_job)
            state.delete_execution_token(normalized_token)
          end

          def finalized_execution_job(running_job:, next_state:, now:, retry_policy:, failure_classification:)
            failed_execution = next_state == :failed
            if failed_execution && retry_policy
              retry_decision = retry_policy.decision_for(
                attempt: running_job.attempt,
                failure_classification:,
                jitter_key: running_job.id
              )
              retry_action = retry_decision.action
              if retry_action == :retry
                return retry_pending_job(
                  running_job,
                  now,
                  retry_policy,
                  failure_classification,
                  now + retry_decision.delay
                )
              end
              if retry_action == :escalate
                failed_job = running_job.transition_to(
                  :failed,
                  updated_at: now,
                  next_retry_at: nil,
                  failure_classification:
                )
                dead_letter_reason =
                  retry_decision.reason == :retry_exhausted ? DeadLetterSupport::RETRY_EXHAUSTED_REASON : DeadLetterSupport::CLASSIFICATION_ESCALATED_REASON
                return failed_job.transition_to(
                  :dead_letter,
                  updated_at: now,
                  next_retry_at: nil,
                  failure_classification: failed_job.failure_classification,
                  dead_letter_reason:,
                  dead_lettered_at: now,
                  dead_letter_source_state: failed_job.state
                )
              end
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
end
