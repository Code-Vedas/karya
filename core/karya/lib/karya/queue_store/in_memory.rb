# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require 'bigdecimal'

require_relative 'base'
require_relative '../internal/failure_classification'
require_relative '../internal/retry_policy_normalizer'
require_relative 'recovery_report'
require_relative 'in_memory/backpressure_support'
require_relative 'in_memory/expiration_support'
require_relative 'in_memory/execution_support'
require_relative 'in_memory/execution_recovery'
require_relative 'in_memory/handler_matcher'
require_relative 'in_memory/lease_duration'
require_relative 'in_memory/recovery_support'
require_relative 'in_memory/request_support'
require_relative 'in_memory/reserve_selection_support'
require_relative 'in_memory/retry_support'
require_relative 'in_memory/reserve_scan_state'
require_relative 'in_memory/store_state'
require_relative 'in_memory/uniqueness_support'
require_relative '../job'
require_relative '../primitives/identifier'
require_relative '../primitives/queue_list'
require_relative '../reservation'
require_relative '../retry_policy'
require_relative '../backpressure'

module Karya
  module QueueStore
    # Single-process reference implementation for queue submission and reservation behavior.
    #
    # InMemory is intentionally ephemeral and suitable for development, tests,
    # examples, and as the executable reference for `QueueStore::Base`
    # semantics. It is not a durable backend: jobs, queue indexes, reservations,
    # active executions, retry state, and expired-token tombstones live only in
    # process memory and are lost on restart. Production deployments that need
    # durable enqueue acknowledgment or restart/takeover recovery must use a
    # shared persistent backend implementing the Base durability contract.
    class InMemory
      include Base
      include BackpressureSupport
      include ExecutionSupport
      include ExpirationSupport
      include RecoverySupport
      include RequestSupport
      include ReserveSelectionSupport
      include RetrySupport
      include UniquenessSupport

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
          idempotency_key = job.idempotency_key
          uniqueness_key = job.uniqueness_key
          jobs_by_id = state.jobs_by_id
          raise DuplicateJobError, "job #{job_id.inspect} is already present in the queue store" if jobs_by_id.key?(job_id)

          expire_reservations_locked(normalized_now)
          raise_duplicate_idempotency_key_error(job_id:, idempotency_key:) if idempotency_conflict?(job)
          raise_duplicate_uniqueness_key_error(job_id:, uniqueness_key:) if uniqueness_conflict?(job)

          queued_job = job.transition_to(:queued, updated_at: normalized_now)
          queued_job_id = queued_job.id
          queue_job_ids = state.queue_job_ids_for(queued_job.queue)
          store_job(job: queued_job)
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
          if job_expired?(reserved_job, normalized_now)
            failed_job = expire_reserved_job(reservation, reserved_job, normalized_now)
            return failed_job
          end

          running_job = reserved_job.transition_to(:running, updated_at: normalized_now, attempt: reserved_job.attempt + 1)
          store_job(job: running_job)
          state.activate_execution(normalized_token, reservation)
          running_job
        end
      end

      def complete_execution(reservation_token:, now:)
        finalize_execution(reservation_token:, now:, next_state: :succeeded)
      end

      def fail_execution(reservation_token:, now:, failure_classification:, retry_policy: nil)
        finalize_execution(reservation_token:, now:, next_state: :failed, retry_policy:, failure_classification:)
      end

      def recover_orphaned_jobs(worker_id:, now:)
        normalized_worker_id = normalize_identifier(:worker_id, worker_id, error_class: InvalidQueueStoreOperationError)
        normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

        @mutex.synchronize do
          recover_in_flight_locked(
            normalized_now,
            worker_id: normalized_worker_id,
            include_global_maintenance: false
          ).recovered_jobs
        end
      end

      def recover_in_flight(now:)
        normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

        @mutex.synchronize { recover_in_flight_locked(normalized_now) }
      end

      def expire_reservations(now:)
        recover_in_flight(now:).jobs
      end

      def expire_jobs(now:)
        normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

        @mutex.synchronize do
          expire_jobs_locked(normalized_now)
        end
      end

      private

      attr_reader :policy_set, :state, :token_generator

      private_constant :LeaseDuration, :HandlerMatcher, :ReserveScanState

      def validate_enqueue(job)
        raise InvalidEnqueueError, 'job must be a Karya::Job' unless job.is_a?(Job)
        raise InvalidEnqueueError, 'job must be in :submission state before enqueue' unless job.state == :submission
      end

      def expire_reservations_locked(now)
        recover_in_flight_locked(now).jobs
      end

      def recover_in_flight_locked(now, worker_id: nil, include_global_maintenance: true)
        expired_reservations = collect_expired_leases(state.reservations_by_token, state.reservation_tokens_in_order, now, worker_id:)
        expired_executions = collect_expired_leases(state.executions_by_token, state.execution_tokens_in_order, now, worker_id:)
        expired_jobs = []
        if include_global_maintenance
          expired_jobs = expire_jobs_locked(now)
          promote_due_retry_pending_jobs(now)
        end

        recovered_reserved_jobs = expired_reservations.map { |reservation| requeue_expired_reservation(reservation, now) }
        recovered_running_jobs = expired_executions.map { |reservation| requeue_expired_execution(reservation, now) }
        prune_stale_rate_limit_admissions(now) if include_global_maintenance
        RecoveryReport.new(
          recovered_at: now,
          expired_jobs:,
          recovered_reserved_jobs:,
          recovered_running_jobs:
        )
      end

      def perform_reserve_maintenance(now)
        expire_reservations_locked(now)
        build_reserve_scan_state
      end

      def normalize_identifier(name, value, error_class:)
        value_class = value.class

        if value_class <= String
          Primitives::Identifier.new(name, value, error_class:).normalize
        elsif value_class <= NilClass
          raise error_class, "#{name} must be present"
        else
          raise error_class, "#{name} must be a String"
        end
      end

      def normalize_time(name, value, error_class:)
        return value if value.is_a?(Time)

        raise error_class, "#{name} must be a Time"
      end

      def reserve_matching_job(reserve_request)
        now = reserve_request.fetch(:now)
        reserve_scan_state = perform_reserve_maintenance(now)
        matched_queue, matched_job_index, matched_job_id =
          find_reserved_job(reserve_request.fetch(:queues), reserve_request.fetch(:handler_matcher), reserve_scan_state)
        return nil unless matched_job_id

        reserve_job(
          matched_queue:,
          matched_job_id:,
          matched_job_index:,
          reserve_request:,
          now:
        )
      end

      def reserve_job(matched_queue:, matched_job_id:, matched_job_index:, reserve_request:, now:)
        queue_job_ids = state.queued_job_ids_by_queue.fetch(matched_queue)
        queued_job = state.jobs_by_id.fetch(matched_job_id)
        reserved_job = queued_job.transition_to(:reserved, updated_at: now)
        reservation = build_reservation(
          reserved_job:,
          worker_id: reserve_request.fetch(:worker_id),
          reserved_at: now,
          lease_duration: reserve_request.fetch(:lease_duration)
        )

        queue_job_ids.delete_at(matched_job_index)
        state.delete_queue(matched_queue) if queue_job_ids.empty?
        store_job(job: reserved_job)
        record_rate_limit_admission(reserved_job, now)
        state.reserve(reservation)
        reservation
      end

      private_constant :ExecutionSupport, :ExpirationSupport, :RecoverySupport, :RequestSupport

      def raise_expired_reservation_error(reservation_token, reservation_label)
        return unless state.expired_reservation_tokens.key?(reservation_token)

        raise ExpiredReservationError, "reservation #{reservation_label} has expired"
      end

      private_constant :ExecutionRecovery, :StoreState
    end
  end
end
