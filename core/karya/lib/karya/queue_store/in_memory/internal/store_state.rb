# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Internal mutable state for the single-process queue store.
        class StoreState
          MAX_TRACKED_FAIR_QUEUE_LISTS = 128

          attr_reader :executions_by_token,
                      :batches_by_id,
                      :breaker_failures_by_scope,
                      :breaker_states_by_scope,
                      :execution_tokens_in_order,
                      :expired_reservation_tokens,
                      :expired_reservation_tokens_in_order,
                      :execution_tokens_by_job_id,
                      :half_open_probe_admissions_by_scope,
                      :jobs_by_id,
                      :last_reserved_queue_by_subscription,
                      :paused_queues,
                      :rate_limit_admissions_by_key,
                      :queued_job_ids_by_queue,
                      :retry_pending_job_ids,
                      :reservation_tokens_by_job_id,
                      :reservation_tokens_in_order,
                      :reservations_by_token,
                      :stuck_job_recoveries_by_id

          def initialize(expired_tombstone_limit:)
            @batches_by_id = {}
            @batch_id_by_job_id = {}
            @breaker_failures_by_scope = {}
            @breaker_states_by_scope = {}
            @executions_by_token = {}
            @execution_tokens_in_order = []
            @expired_reservation_tokens = {}
            @expired_reservation_tokens_in_order = []
            @expired_tombstone_limit = expired_tombstone_limit
            @execution_tokens_by_job_id = {}
            @half_open_probe_admissions_by_scope = {}
            @jobs_by_id = {}
            @last_reserved_queue_by_subscription = {}
            @paused_queues = {}
            @rate_limit_admissions_by_key = {}
            @queued_job_ids_by_queue = {}
            @retry_pending_job_ids = []
            @retry_pending_job_ids_index = {}
            @reservation_tokens_by_job_id = {}
            @reservation_tokens_in_order = []
            @reservations_by_token = {}
            @stuck_job_recoveries_by_id = {}
            @terminal_batch_ids_index = {}
            @terminal_batch_ids_in_order = []
          end

          def queue_job_ids_for(queue)
            queued_job_ids_by_queue[queue] ||= []
          end

          def delete_queue(queue)
            queued_job_ids_by_queue.delete(queue)
          end

          def mark_queue_paused(queue, now)
            return :unchanged if paused_queues.key?(queue)

            paused_queues[queue] = now
            :changed
          end

          def unmark_queue_paused(queue)
            paused_queues.delete(queue) ? :changed : :unchanged
          end

          def queue_paused?(queue)
            paused_queues.key?(queue)
          end

          def last_reserved_queue_for(subscription_key)
            last_reserved_queue_by_subscription[subscription_key]
          end

          def record_reserved_queue(subscription_key, queue)
            last_reserved_queue_by_subscription.delete(subscription_key)
            last_reserved_queue_by_subscription[subscription_key] = queue
            trim_fair_queue_history
            queue
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
            reservation_tokens_by_job_id[reservation.job_id] = reservation_token
            reservation_tokens_in_order << reservation_token
          end

          def activate_execution(reservation_token, reservation)
            delete_reservation_token(reservation_token)
            executions_by_token[reservation_token] = reservation
            execution_tokens_by_job_id[reservation.job_id] = reservation_token
            execution_tokens_in_order << reservation_token
          end

          def reservation_token_for_job(job_id)
            reservation_tokens_by_job_id[job_id]
          end

          def execution_token_for_job(job_id)
            execution_tokens_by_job_id[job_id]
          end

          def delete_reservation_token(reservation_token)
            reservation = reservations_by_token.delete(reservation_token)
            reservation_tokens_by_job_id.delete(reservation.job_id) if reservation
            reservation_index = reservation_tokens_in_order.index(reservation_token)
            reservation_tokens_in_order.delete_at(reservation_index) if reservation_index
          end

          def delete_execution_token(reservation_token)
            reservation = executions_by_token.delete(reservation_token)
            execution_tokens_by_job_id.delete(reservation.job_id) if reservation
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

          def register_batch(batch)
            batch_id = batch.id
            batches_by_id[batch_id] = batch
            batch.job_ids.each { |job_id| @batch_id_by_job_id[job_id] = batch_id }
            if terminal_batch?(batch) && !@terminal_batch_ids_index[batch_id]
              @terminal_batch_ids_index[batch_id] = true
              @terminal_batch_ids_in_order << batch_id
            end
            batch
          end

          def prune_terminal_batches(retention_limit, changed_job: nil)
            if changed_job
              batch_id = @batch_id_by_job_id[changed_job.id]
              batch = batches_by_id[batch_id]
              if batch
                batch_terminal = terminal_batch?(batch)
                batch_tracked = @terminal_batch_ids_index[batch_id]
                case [batch_terminal, batch_tracked]
                when [true, false], [true, nil]
                  @terminal_batch_ids_index[batch_id] = true
                  @terminal_batch_ids_in_order << batch_id
                when [false, true]
                  @terminal_batch_ids_index[batch_id] = false
                  @terminal_batch_ids_in_order.delete(batch_id)
                end
              end
            end

            pruned_batch_ids = []

            while @terminal_batch_ids_in_order.length > retention_limit
              batch_id = @terminal_batch_ids_in_order.shift
              @terminal_batch_ids_index.delete(batch_id)
              batch = batches_by_id.delete(batch_id)
              next unless batch

              batch.job_ids.each { |job_id| @batch_id_by_job_id.delete(job_id) }
              pruned_batch_ids << batch_id
            end

            pruned_batch_ids
          end

          private

          def terminal_batch?(batch)
            batch.job_ids.all? do |job_id|
              job = jobs_by_id[job_id]
              job&.terminal?
            end
          end

          def trim_fair_queue_history
            last_reserved_queue_by_subscription.shift while last_reserved_queue_by_subscription.length > MAX_TRACKED_FAIR_QUEUE_LISTS
          end

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
end
