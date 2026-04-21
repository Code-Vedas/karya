# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Internal mutable state for the single-process queue store.
      class StoreState
        attr_reader :executions_by_token,
                    :breaker_failures_by_scope,
                    :breaker_states_by_scope,
                    :execution_tokens_in_order,
                    :expired_reservation_tokens,
                    :expired_reservation_tokens_in_order,
                    :half_open_probe_admissions_by_scope,
                    :jobs_by_id,
                    :rate_limit_admissions_by_key,
                    :queued_job_ids_by_queue,
                    :retry_pending_job_ids,
                    :reservation_tokens_in_order,
                    :reservations_by_token,
                    :stuck_job_recoveries_by_id

        def initialize(expired_tombstone_limit:)
          @breaker_failures_by_scope = {}
          @breaker_states_by_scope = {}
          @executions_by_token = {}
          @execution_tokens_in_order = []
          @expired_reservation_tokens = {}
          @expired_reservation_tokens_in_order = []
          @expired_tombstone_limit = expired_tombstone_limit
          @half_open_probe_admissions_by_scope = {}
          @jobs_by_id = {}
          @rate_limit_admissions_by_key = {}
          @queued_job_ids_by_queue = {}
          @retry_pending_job_ids = []
          @retry_pending_job_ids_index = {}
          @reservation_tokens_in_order = []
          @reservations_by_token = {}
          @stuck_job_recoveries_by_id = {}
        end

        def queue_job_ids_for(queue)
          queued_job_ids_by_queue[queue] ||= []
        end

        def delete_queue(queue)
          queued_job_ids_by_queue.delete(queue)
        end

        def register_retry_pending(job_id)
          unless @retry_pending_job_ids_index.key?(job_id)
            retry_pending_job_ids << job_id
            @retry_pending_job_ids_index[job_id] = true
          end

          retry_pending_job_ids
        end

        def delete_retry_pending(job_id)
          @retry_pending_job_ids_index.delete(job_id)
          retry_pending_job_ids.delete(job_id)
        end

        def rate_limit_admissions_for(key)
          rate_limit_admissions_by_key[key] ||= []
        end

        def breaker_failures_for(key)
          breaker_failures_by_scope[key] ||= []
        end

        def half_open_probe_admissions_for(key)
          half_open_probe_admissions_by_scope[key] ||= []
        end

        def delete_rate_limit_key(key)
          rate_limit_admissions_by_key.delete(key)
        end

        def clear_half_open_probe_admissions(key)
          half_open_probe_admissions_by_scope.delete(key)
        end

        def register_stuck_job_recovery(job_id:, now:, reason:)
          existing_recovery = stuck_job_recoveries_by_id[job_id]
          stuck_job_recoveries_by_id[job_id] = {
            recovery_count: existing_recovery ? existing_recovery.fetch(:recovery_count) + 1 : 1,
            last_recovered_at: now,
            last_recovery_reason: reason
          }
        end

        def reserve(reservation)
          reservation_token = reservation.token
          reservations_by_token[reservation_token] = reservation
          reservation_tokens_in_order << reservation_token
        end

        def activate_execution(reservation_token, reservation)
          reservations_by_token.delete(reservation_token)
          delete_reservation_token(reservation_token)
          executions_by_token[reservation_token] = reservation
          execution_tokens_in_order << reservation_token
        end

        def delete_reservation_token(reservation_token)
          reservation_index = reservation_tokens_in_order.index(reservation_token)
          reservation_tokens_in_order.delete_at(reservation_index) if reservation_index
        end

        def delete_execution_token(reservation_token)
          execution_index = execution_tokens_in_order.index(reservation_token)
          execution_tokens_in_order.delete_at(execution_index) if execution_index
        end

        def mark_expired(reservation_token)
          return if expired_reservation_tokens.key?(reservation_token)

          expired_reservation_tokens[reservation_token] = true
          expired_reservation_tokens_in_order << reservation_token
          prune_expired_reservation_tokens
        end

        def reservation_token_in_use?(reservation_token)
          reservations_by_token.key?(reservation_token) ||
            executions_by_token.key?(reservation_token) ||
            expired_reservation_tokens.key?(reservation_token)
        end

        private

        def prune_expired_reservation_tokens
          while expired_reservation_tokens_in_order.length > @expired_tombstone_limit
            oldest_token = expired_reservation_tokens_in_order.shift
            expired_reservation_tokens.delete(oldest_token)
          end
        end
      end
    end
  end
end
