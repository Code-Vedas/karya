# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    module Internal
      module ReferenceQueueStore
        module Internal
          # Detects whether read-mostly or reserve operations actually changed store state.
          module PersistenceOutcomeSupport
            private

            def reserve_with_persistence_outcome(handler_matcher:, lease_duration:, now:, queues:, subscription_key:, worker_id:)
              initial_fingerprint = persistence_relevant_state_fingerprint
              reservation = reserve_matching_job(
                handler_matcher:,
                lease_duration:,
                now:,
                queues:,
                subscription_key:,
                worker_id:
              )
              {
                reservation:,
                persist: reservation ? true : initial_fingerprint != persistence_relevant_state_fingerprint
              }
            end

            def inspection_snapshot_outcome
              initial_fingerprint = persistence_relevant_state_fingerprint
              {
                snapshot: yield,
                persist: initial_fingerprint != persistence_relevant_state_fingerprint
              }
            end

            def persistence_relevant_state_fingerprint
              Marshal.dump(persistence_relevant_state_payload)
            end

            def persistence_relevant_state_payload
              lease_persistence_state
                .merge(queue_persistence_state)
                .merge(reliability_persistence_state)
                .merge(reservation_token_sequence: @reservation_token_sequence)
            end

            def lease_persistence_state
              {
                execution_tokens_by_job_id: state.execution_tokens_by_job_id,
                execution_tokens_in_order: state.execution_tokens_in_order,
                executions_by_token: state.executions_by_token,
                expired_reservation_tokens: state.expired_reservation_tokens,
                expired_reservation_tokens_in_order: state.expired_reservation_tokens_in_order,
                reservation_tokens_by_job_id: state.reservation_tokens_by_job_id,
                reservation_tokens_in_order: state.reservation_tokens_in_order,
                reservations_by_token: state.reservations_by_token
              }
            end

            def queue_persistence_state
              {
                jobs_by_id: state.jobs_by_id,
                last_reserved_queue_by_subscription: state.last_reserved_queue_by_subscription,
                queued_job_ids_by_queue: state.queued_job_ids_by_queue,
                rate_limit_admissions_by_key: state.rate_limit_admissions_by_key,
                retry_pending_job_ids: state.retry_pending_job_ids
              }
            end

            def reliability_persistence_state
              {
                breaker_failures_by_scope: state.breaker_failures_by_scope,
                breaker_states_by_scope: state.breaker_states_by_scope,
                half_open_probe_admissions_by_scope: state.half_open_probe_admissions_by_scope,
                stuck_job_recoveries_by_id: state.stuck_job_recoveries_by_id
              }
            end
          end
        end
      end
    end
  end
end
