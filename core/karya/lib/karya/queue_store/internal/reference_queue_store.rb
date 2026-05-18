# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../base'
require_relative '../internal'
require_relative 'reference_queue_store/internal'

module Karya
  module QueueStore
    module Internal
      # Shared reference queue-store behavior used by concrete store implementations.
      module ReferenceQueueStore
        include Karya::QueueStore::Base

        DEFAULT_EXPIRED_TOMBSTONE_LIMIT = 1024
        DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT = 1024
        DEFAULT_MAX_BATCH_SIZE = 1000
        RESERVE_QUEUES_ERROR_MESSAGE = 'provide exactly one of queue or queues'
        InitializerOptions = Karya::QueueStore::Internal.const_get(:InitializerOptions, false)
        # Neutral aliases for the shared reference-store internals.
        module Internal; end
        Internal.const_set(:StoreState, Karya::QueueStore::Internal.const_get(:StoreState, false))
        %i[
          BatchSupport
          BackpressureSupport
          BackpressureSnapshotSupport
          ChildWorkflowSupport
          DeadLetterSupport
          ExecutionSupport
          ExpirationSupport
          OperationsSupport
          ReliabilitySupport
          ReliabilitySnapshotSupport
          RecoverySupport
          RequestSupport
          ReserveSelectionSupport
          RetrySupport
          UniquenessSupport
          ValidationSupport
          WorkflowCheckpointSupport
          WorkflowHistorySupport
          WorkflowSupport
        ].each do |name|
          include Internal.const_get(name, false)
        end

        def configure_reference_queue_store(initializer_options_class:, store_state_class:, **options)
          initializer_options = initializer_options_class.new(options)
          expired_tombstone_limit = initializer_options.expired_tombstone_limit
          completed_batch_retention_limit = initializer_options.completed_batch_retention_limit
          max_batch_size = initializer_options.max_batch_size
          token_generator = initializer_options.token_generator
          policy_set = initializer_options.policy_set
          circuit_breaker_policy_set = initializer_options.circuit_breaker_policy_set
          fairness_policy = initializer_options.fairness_policy

          validate_initializer_limits(expired_tombstone_limit:, completed_batch_retention_limit:, max_batch_size:)
          Primitives::Callable.new(:token_generator, token_generator, error_class: InvalidQueueStoreOperationError).normalize
          raise InvalidQueueStoreOperationError, 'policy_set must be a Karya::Backpressure::PolicySet' unless policy_set.is_a?(Backpressure::PolicySet)
          raise InvalidQueueStoreOperationError, 'fairness_policy must be a Karya::Fairness::Policy' unless fairness_policy.is_a?(Fairness::Policy)
          unless circuit_breaker_policy_set.is_a?(CircuitBreaker::PolicySet)
            raise InvalidQueueStoreOperationError,
                  'circuit_breaker_policy_set must be a Karya::CircuitBreaker::PolicySet'
          end

          @token_generator = token_generator
          @expired_tombstone_limit = expired_tombstone_limit
          @completed_batch_retention_limit = completed_batch_retention_limit
          @max_batch_size = max_batch_size
          @policy_set = policy_set
          @circuit_breaker_policy_set = circuit_breaker_policy_set
          @fairness_policy = fairness_policy
          @reservation_token_sequence = 0
          @mutex = Internal::ReadOnlyMutex.new
          @state = store_state_class.new(expired_tombstone_limit:)
        end

        def enqueue(job:, now:)
          normalized_now = normalize_time(:now, now, error_class: InvalidEnqueueError)
          @mutex.synchronize do
            validate_enqueue(job)
            duplicate_decision = build_uniqueness_decision(job, normalized_now)
            raise_duplicate_enqueue_error(duplicate_decision) if duplicate_decision.fetch(:action) == :reject
            expire_reservations_locked(normalized_now)
            enqueue_validated_job(job, normalized_now)
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
          reserve_outcome = @mutex.synchronize(persist_if: ->(outcome) { outcome.fetch(:persist) }) do
            reserve_matching_job(**reserve_request)
          end
          reserve_outcome.fetch(:reservation)
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

        def backpressure_snapshot(now:)
          normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

          snapshot_outcome = @mutex.synchronize(persist_if: ->(outcome) { outcome.fetch(:persist) }) do
            persist = prepare_backpressure_snapshot(normalized_now)
            {
              snapshot: build_backpressure_snapshot(normalized_now),
              persist:
            }
          end
          snapshot_outcome.fetch(:snapshot)
        end

        def reliability_snapshot(now:)
          normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

          snapshot_outcome = @mutex.synchronize(persist_if: ->(outcome) { outcome.fetch(:persist) }) do
            persist = prepare_reliability_snapshot(normalized_now)
            {
              snapshot: build_reliability_snapshot(normalized_now),
              persist:
            }
          end
          snapshot_outcome.fetch(:snapshot)
        end

        def uniqueness_decision(job:, now:)
          normalized_now = normalize_time(:now, now, error_class: InvalidEnqueueError)

          @mutex.read_only_synchronize do
            validate_enqueue(job)
            build_uniqueness_decision(job, normalized_now)
          end
        end

        def uniqueness_snapshot(now:)
          normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

          @mutex.read_only_synchronize do
            build_uniqueness_snapshot(normalized_now)
          end
        end

        private

        attr_reader :circuit_breaker_policy_set,
                    :completed_batch_retention_limit,
                    :expired_tombstone_limit,
                    :fairness_policy,
                    :max_batch_size,
                    :policy_set,
                    :state,
                    :token_generator

        def validate_enqueue(job)
          raise InvalidEnqueueError, 'job must be a Karya::Job' unless job.is_a?(Job)
          raise InvalidEnqueueError, 'job must be in :submission state before enqueue' unless job.state == :submission
        end

        def expire_reservations_locked(now)
          recover_in_flight_locked(now).jobs
        end

        def prepare_backpressure_snapshot(now)
          expired_reservations = collect_expired_leases(state.reservations_by_token, state.reservation_tokens_in_order, now)
          expired_executions = collect_expired_leases(state.executions_by_token, state.execution_tokens_in_order, now)
          expired_reservations.each { |reservation| requeue_expired_reservation(reservation, now) }
          expired_executions.each { |reservation| requeue_expired_execution(reservation, now) }
          expired_reservations.any? || expired_executions.any? || prune_stale_rate_limit_admissions(now)
        end

        def recover_in_flight_locked(now, worker_id: nil, include_global_maintenance: true)
          expired_reservations = collect_expired_leases(state.reservations_by_token, state.reservation_tokens_in_order, now, worker_id:)
          expired_executions = collect_expired_leases(state.executions_by_token, state.execution_tokens_in_order, now, worker_id:)
          expired_jobs = []
          promoted_retry_pending = false
          pruned_rate_limit_admissions = false
          if include_global_maintenance
            expired_jobs = expire_jobs_locked(now)
            promoted_retry_pending = promote_due_retry_pending_jobs(now)
          end

          recovered_reserved_jobs = expired_reservations.map { |reservation| requeue_expired_reservation(reservation, now) }
          recovered_running_jobs = expired_executions.map { |reservation| requeue_expired_execution(reservation, now) }
          pruned_rate_limit_admissions = prune_stale_rate_limit_admissions(now) if include_global_maintenance
          QueueStore::Internal::RecoveryReport.new(
            recovered_at: now,
            expired_jobs:,
            recovered_reserved_jobs:,
            recovered_running_jobs:,
            changed: expired_jobs.any? ||
              recovered_reserved_jobs.any? ||
              recovered_running_jobs.any? ||
              promoted_retry_pending ||
              pruned_rate_limit_admissions
          )
        end

        def perform_reserve_maintenance(now)
          recovered_jobs = expire_reservations_locked(now)
          {
            reserve_scan_state: build_reserve_scan_state,
            persist: !recovered_jobs.empty?
          }
        end

        def store_and_requeue_if_needed(job, queue:, job_id:, state_name:)
          store_job(job:)
          requeue_job_if_needed(queue, job_id, state_name)
          job
        end

        def requeue_job_if_needed(queue, job_id, state_name)
          return unless state_name == :queued

          state.queue_job_ids_for(queue) << job_id
        end

        def reserve_matching_job(handler_matcher:, lease_duration:, now:, queues:, subscription_key:, worker_id:)
          maintenance = perform_reserve_maintenance(now)
          reserve_scan_state = maintenance.fetch(:reserve_scan_state)
          matched_queue, matched_job_index, matched_job_id =
            find_reserved_job(
              queues,
              subscription_key,
              handler_matcher,
              reserve_scan_state,
              now
            )
          return { reservation: nil, persist: maintenance.fetch(:persist) } unless matched_job_id

          {
            reservation: reserve_job(
              matched_queue:,
              matched_job_id:,
              matched_job_index:,
              lease_duration:,
              now:,
              queues:,
              subscription_key:,
              worker_id:
            ),
            persist: true
          }
        end

        def reserve_job(matched_queue:, matched_job_id:, matched_job_index:, worker_id:, lease_duration:, queues:, subscription_key:, now:)
          queue_job_ids = state.queued_job_ids_by_queue.fetch(matched_queue)
          queued_job = state.jobs_by_id.fetch(matched_job_id)
          reserved_job = queued_job.transition_to(:reserved, updated_at: now)
          reservation = build_reservation(
            reserved_job:,
            worker_id:,
            reserved_at: now,
            lease_duration:
          )

          queue_job_ids.delete_at(matched_job_index)
          state.delete_queue(matched_queue) if queue_job_ids.empty?
          store_job(job: reserved_job)
          record_rate_limit_admission(reserved_job, now)
          state.reserve(reservation)
          state.record_reserved_queue(subscription_key, matched_queue) if track_fairness_history?(queues)
          register_half_open_probe(reserved_job, reservation.token, now)
          reservation
        end

        def track_fairness_history?(queues)
          fairness_policy.strategy == :round_robin && queues.length > 1
        end

        def raise_expired_reservation_error(reservation_token, reservation_label)
          return unless state.expired_reservation_tokens.key?(reservation_token)

          raise ExpiredReservationError, "reservation #{reservation_label} has expired"
        end
      end
    end
  end
end
