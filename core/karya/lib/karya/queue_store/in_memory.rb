# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require 'bigdecimal'

require_relative 'base'
require_relative '../job'
require_relative '../reservation'

module Karya
  module QueueStore
    # Single-process reference implementation for queue submission and reservation behavior.
    class InMemory
      include Base

      DEFAULT_EXPIRED_TOMBSTONE_LIMIT = 1024

      def initialize(token_generator: -> { SecureRandom.uuid }, expired_tombstone_limit: DEFAULT_EXPIRED_TOMBSTONE_LIMIT)
        valid_tombstone_limit = expired_tombstone_limit.is_a?(Integer) && expired_tombstone_limit >= 0
        raise InvalidQueueStoreOperationError, 'expired_tombstone_limit must be a finite non-negative Integer' unless valid_tombstone_limit

        @token_generator = token_generator
        @reservation_token_sequence = 0
        @mutex = Mutex.new
        @state = StoreState.new(expired_tombstone_limit:)
      end

      def enqueue(job:, now:)
        normalized_now = normalize_time(:now, now, error_class: InvalidEnqueueError)

        @mutex.synchronize do
          validate_enqueue(job)

          job_id = job.id
          jobs_by_id = state.jobs_by_id
          raise DuplicateJobError, "job #{job_id.inspect} is already present in the queue store" if jobs_by_id.key?(job_id)

          expire_reservations_locked(normalized_now)

          queued_job = job.transition_to(:queued, updated_at: normalized_now)
          queued_job_id = queued_job.id
          queue_job_ids = state.queue_job_ids_for(queued_job.queue)
          jobs_by_id[queued_job_id] = queued_job
          queue_job_ids << queued_job_id
          queued_job
        end
      end

      def reserve(queue:, worker_id:, lease_duration:, now:)
        normalized_queue = normalize_identifier(:queue, queue, error_class: InvalidQueueStoreOperationError)
        normalized_worker_id = normalize_identifier(:worker_id, worker_id, error_class: InvalidQueueStoreOperationError)
        normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)
        normalized_lease_duration = LeaseDuration.new(lease_duration).normalize

        @mutex.synchronize do
          expire_reservations_locked(normalized_now)

          queue_job_ids = state.queued_job_ids_by_queue.fetch(normalized_queue, [])
          job_id = queue_job_ids.first
          return nil unless job_id

          jobs_by_id = state.jobs_by_id
          queued_job = jobs_by_id.fetch(job_id)
          reserved_job = queued_job.transition_to(:reserved, updated_at: normalized_now)
          reservation = build_reservation(
            reserved_job:,
            worker_id: normalized_worker_id,
            reserved_at: normalized_now,
            lease_duration: normalized_lease_duration
          )

          queue_job_ids.shift
          state.delete_queue(normalized_queue) if queue_job_ids.empty?
          jobs_by_id[reserved_job.id] = reserved_job
          state.reserve(reservation)
          reservation
        end
      end

      def release(reservation_token:, now:)
        normalized_token = normalize_identifier(:reservation_token, reservation_token, error_class: InvalidQueueStoreOperationError)
        normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

        @mutex.synchronize do
          reservation = fetch_active_reservation(normalized_token, normalized_now)
          requeue_reservation(reservation, normalized_now)
        end
      end

      def start_execution(reservation_token:, now:)
        normalized_token = normalize_identifier(:reservation_token, reservation_token, error_class: InvalidQueueStoreOperationError)
        normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

        @mutex.synchronize do
          reservation = fetch_active_reservation(normalized_token, normalized_now)
          jobs_by_id = state.jobs_by_id
          reserved_job = jobs_by_id.fetch(reservation.job_id)
          running_job = reserved_job.transition_to(:running, updated_at: normalized_now, attempt: reserved_job.attempt + 1)
          jobs_by_id[running_job.id] = running_job
          state.activate_execution(normalized_token, reservation)
          running_job
        end
      end

      def complete_execution(reservation_token:, now:)
        finalize_execution(reservation_token:, now:, next_state: :succeeded)
      end

      def fail_execution(reservation_token:, now:)
        finalize_execution(reservation_token:, now:, next_state: :failed)
      end

      def expire_reservations(now:)
        normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

        @mutex.synchronize do
          expire_reservations_locked(normalized_now)
        end
      end

      private

      attr_reader :state, :token_generator

      # Internal mutable state for the single-process queue store.
      class StoreState
        attr_reader :executions_by_token,
                    :execution_tokens_in_order,
                    :expired_reservation_tokens,
                    :expired_reservation_tokens_in_order,
                    :jobs_by_id,
                    :queued_job_ids_by_queue,
                    :reservation_tokens_in_order,
                    :reservations_by_token

        def initialize(expired_tombstone_limit:)
          @executions_by_token = {}
          @execution_tokens_in_order = []
          @expired_reservation_tokens = {}
          @expired_reservation_tokens_in_order = []
          @expired_tombstone_limit = expired_tombstone_limit
          @jobs_by_id = {}
          @queued_job_ids_by_queue = {}
          @reservation_tokens_in_order = []
          @reservations_by_token = {}
        end

        def queue_job_ids_for(queue)
          queued_job_ids_by_queue[queue] ||= []
        end

        def delete_queue(queue)
          queued_job_ids_by_queue.delete(queue)
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

      # Validates and normalizes lease durations accepted by the queue store.
      class LeaseDuration
        def initialize(value)
          @value = value
        end

        def normalize
          raise InvalidQueueStoreOperationError, 'lease_duration must be a positive number' unless valid?

          value
        end

        private

        attr_reader :value

        def valid?
          case value
          when Integer, Float, Rational, BigDecimal
            value.positive? && (value.is_a?(Integer) || value.finite?)
          else
            false
          end
        end
      end

      private_constant :LeaseDuration

      def validate_enqueue(job)
        raise InvalidEnqueueError, 'job must be a Karya::Job' unless job.is_a?(Job)
        raise InvalidEnqueueError, 'job must be in :submission state before enqueue' unless job.state == :submission
      end

      def next_token
        base_token = normalize_identifier(:token, token_generator.call, error_class: InvalidQueueStoreOperationError)
        @reservation_token_sequence += 1
        "#{base_token}:#{@reservation_token_sequence}"
      end

      def expire_reservations_locked(now)
        expired_reservations = collect_expired_leases(state.reservations_by_token, state.reservation_tokens_in_order, now)
        expired_executions = collect_expired_leases(state.executions_by_token, state.execution_tokens_in_order, now)

        expired_reserved_jobs = expired_reservations.map { |reservation| requeue_expired_reservation(reservation, now) }
        expired_running_jobs = expired_executions.map { |reservation| requeue_expired_execution(reservation, now) }
        expired_reserved_jobs + expired_running_jobs
      end

      def requeue_reservation(reservation, now)
        reservation_token = reservation.token
        jobs_by_id = state.jobs_by_id
        state.reservations_by_token.delete(reservation_token)
        state.delete_reservation_token(reservation_token)

        reserved_job = jobs_by_id.fetch(reservation.job_id)
        queued_job = reserved_job.transition_to(:queued, updated_at: now)
        queued_job_id = queued_job.id
        jobs_by_id[queued_job_id] = queued_job
        state.queue_job_ids_for(queued_job.queue) << queued_job_id
        queued_job
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
        queued_job_id = queued_job.id
        jobs_by_id[queued_job_id] = queued_job
        state.queue_job_ids_for(queued_job.queue) << queued_job_id
        state.mark_expired(reservation_token)
        queued_job
      end

      def normalize_identifier(name, value, error_class:)
        normalized_value = value.to_s.strip
        raise error_class, "#{name} must be present" if normalized_value.empty?

        normalized_value
      end

      def normalize_time(name, value, error_class:)
        return value if value.is_a?(Time)

        raise error_class, "#{name} must be a Time"
      end

      def build_reservation(reserved_job:, worker_id:, reserved_at:, lease_duration:)
        reservation_token = next_token
        ensure_unique_reservation_token(reservation_token)

        Reservation.new(
          token: reservation_token,
          job_id: reserved_job.id,
          queue: reserved_job.queue,
          worker_id:,
          reserved_at:,
          expires_at: reserved_at + lease_duration
        )
      end

      def ensure_unique_reservation_token(reservation_token)
        return unless state.reservation_token_in_use?(reservation_token)

        raise DuplicateReservationTokenError,
              "reservation token #{reservation_token.inspect} is already in use (active or expired)"
      end

      def finalize_execution(reservation_token:, now:, next_state:)
        normalized_token = normalize_identifier(:reservation_token, reservation_token, error_class: InvalidQueueStoreOperationError)
        normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

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

          jobs_by_id = state.jobs_by_id
          running_job = jobs_by_id.fetch(reservation.job_id)
          finalized_job = running_job.transition_to(next_state, updated_at: normalized_now)
          jobs_by_id[finalized_job.id] = finalized_job
          executions_by_token.delete(normalized_token)
          state.delete_execution_token(normalized_token)
          finalized_job
        end
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

      def collect_expired_leases(leases_by_token, tokens_in_order, now)
        self.class.send(:collect_expired_leases, leases_by_token, tokens_in_order, now)
      end

      def self.collect_expired_leases(leases_by_token, tokens_in_order, now)
        tokens_in_order.filter_map do |token|
          reservation = leases_by_token.fetch(token)
          reservation if reservation.expired?(now)
        end
      end

      private_class_method :collect_expired_leases

      def raise_expired_reservation_error(reservation_token, reservation_label)
        return unless state.expired_reservation_tokens.key?(reservation_token)

        raise ExpiredReservationError, "reservation #{reservation_label} has expired"
      end

      # Rebuilds a running job as queued when execution lease recovery is required.
      class ExecutionRecovery
        def initialize(running_job, now)
          @running_job = running_job
          @now = now
        end

        def to_queued_job
          running_job.transition_to(:queued, updated_at: now)
        end

        private

        attr_reader :now, :running_job
      end

      private_constant :ExecutionRecovery, :StoreState
    end
  end
end
