# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require 'bigdecimal'

require_relative 'base'
require_relative 'in_memory/backpressure_support'
require_relative 'in_memory/handler_matcher'
require_relative 'in_memory/lease_duration'
require_relative 'in_memory/reserve_scan_state'
require_relative 'in_memory/store_state'
require_relative '../job'
require_relative '../primitives/identifier'
require_relative '../primitives/queue_list'
require_relative '../reservation'
require_relative '../backpressure'

module Karya
  module QueueStore
    # Single-process reference implementation for queue submission and reservation behavior.
    class InMemory
      include Base
      include BackpressureSupport

      DEFAULT_EXPIRED_TOMBSTONE_LIMIT = 1024
      RESERVE_QUEUES_ERROR_MESSAGE = 'provide exactly one of queue or queues'

      def initialize(
        token_generator: -> { SecureRandom.uuid },
        expired_tombstone_limit: DEFAULT_EXPIRED_TOMBSTONE_LIMIT,
        policy_set: Backpressure::PolicySet.new
      )
        valid_tombstone_limit = expired_tombstone_limit.is_a?(Integer) && expired_tombstone_limit >= 0
        raise InvalidQueueStoreOperationError, 'expired_tombstone_limit must be a finite non-negative Integer' unless valid_tombstone_limit
        raise InvalidQueueStoreOperationError, 'policy_set must be a Karya::Backpressure::PolicySet' unless policy_set.is_a?(Backpressure::PolicySet)

        @token_generator = token_generator
        @policy_set = policy_set
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

      def reserve(worker_id:, lease_duration:, now:, queue: nil, queues: nil, handler_names: nil)
        reserve_request = normalize_reserve_request(
          worker_id:,
          lease_duration:,
          now:,
          queue:,
          queues:,
          handler_names:
        )

        @mutex.synchronize { reserve_matching_job(reserve_request) }
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

      attr_reader :policy_set, :state, :token_generator

      private_constant :LeaseDuration, :HandlerMatcher, :ReserveScanState

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
        prune_stale_rate_limit_admissions(now)
        expired_reserved_jobs + expired_running_jobs
      end

      def perform_reserve_maintenance(now)
        expire_reservations_locked(now)
        build_reserve_scan_state
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

      def normalize_reserve_queues(queue:, queues:)
        reserve_queues = queue && queues ? nil : queue || queues
        raise InvalidQueueStoreOperationError, RESERVE_QUEUES_ERROR_MESSAGE unless reserve_queues

        Primitives::QueueList.new(reserve_queues, error_class: InvalidQueueStoreOperationError).normalize
      end

      def normalize_reserve_request(worker_id:, lease_duration:, now:, queue:, queues:, handler_names:)
        {
          handler_matcher: HandlerMatcher.new(handler_names),
          lease_duration: LeaseDuration.new(lease_duration).normalize,
          now: normalize_time(:now, now, error_class: InvalidQueueStoreOperationError),
          queues: normalize_reserve_queues(queue:, queues:),
          worker_id: normalize_identifier(:worker_id, worker_id, error_class: InvalidQueueStoreOperationError)
        }
      end

      def reserve_matching_job(reserve_request)
        now = reserve_request.fetch(:now)
        reserve_scan_state = perform_reserve_maintenance(now)
        matched_queue, matched_job_index, matched_job_id =
          find_reserved_job(reserve_request.fetch(:queues), reserve_request.fetch(:handler_matcher), reserve_scan_state)
        return nil unless matched_job_id

        jobs_by_id = state.jobs_by_id
        queue_job_ids = state.queued_job_ids_by_queue.fetch(matched_queue)
        queued_job = jobs_by_id.fetch(matched_job_id)
        reserved_job = queued_job.transition_to(:reserved, updated_at: now)
        reservation = build_reservation(
          reserved_job:,
          worker_id: reserve_request.fetch(:worker_id),
          reserved_at: now,
          lease_duration: reserve_request.fetch(:lease_duration)
        )

        queue_job_ids.delete_at(matched_job_index)
        state.delete_queue(matched_queue) if queue_job_ids.empty?
        jobs_by_id[reserved_job.id] = reserved_job
        record_rate_limit_admission(reserved_job, now)
        state.reserve(reservation)
        reservation
      end

      def find_reserved_job(queues, handler_matcher, reserve_scan_state)
        queues.each do |queue|
          matched_job_index, matched_job_id = matching_job_for(queue, handler_matcher, reserve_scan_state)
          return [queue, matched_job_index, matched_job_id] if matched_job_id
        end

        nil
      end

      def matching_job_for(queue, handler_matcher, reserve_scan_state)
        queue_job_ids = state.queued_job_ids_by_queue.fetch(queue, [])
        selected_job_id = nil
        selected_job_index = nil
        selected_job_priority = nil

        queue_job_ids.each_with_index do |job_id, index|
          queued_job = state.jobs_by_id.fetch(job_id)
          queued_job_priority = queued_job.priority
          next unless handler_matcher.include?(queued_job.handler)
          next if reserve_scan_state.concurrency_blocked?(queued_job)
          next if reserve_scan_state.rate_limited?(queued_job)
          next if selected_job_priority && queued_job_priority <= selected_job_priority

          selected_job_id = job_id
          selected_job_index = index
          selected_job_priority = queued_job_priority
        end

        return nil unless selected_job_id

        [selected_job_index, selected_job_id]
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
