# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require 'bigdecimal'

require_relative 'base'
require_relative 'bulk_mutation_report'
require_relative '../circuit_breaker'
require_relative '../fairness'
require_relative '../internal/bulk_mutation'
require_relative '../internal/failure_classification'
require_relative '../internal/retry_policy_normalizer'
require_relative 'queue_control_result'
require_relative 'recovery_report'
require_relative 'in_memory/internal'
require_relative '../job'
require_relative '../primitives/callable'
require_relative '../primitives/identifier'
require_relative '../primitives/queue_list'
require_relative '../reservation'
require_relative '../retry_policy'
require_relative '../backpressure'
require_relative '../workflow'

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
      # Owner-local implementation helpers for the executable reference store.
      module Internal
      end

      include Base
      include Internal::BatchSupport
      include Internal::BackpressureSupport
      include Internal::BackpressureSnapshotSupport
      include Internal::DeadLetterSupport
      include Internal::ExecutionSupport
      include Internal::ExpirationSupport
      include Internal::OperationsSupport
      include Internal::ReliabilitySupport
      include Internal::ReliabilitySnapshotSupport
      include Internal::RecoverySupport
      include Internal::RequestSupport
      include Internal::ReserveSelectionSupport
      include Internal::RetrySupport
      include Internal::UniquenessSupport

      DEFAULT_EXPIRED_TOMBSTONE_LIMIT = 1024
      DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT = 1024
      DEFAULT_MAX_BATCH_SIZE = 1000
      RESERVE_QUEUES_ERROR_MESSAGE = 'provide exactly one of queue or queues'

      # Normalizes constructor keyword options without growing the initializer
      # parameter list as queue-store capabilities expand.
      class InitializerOptions
        # Reads constructor keyword options with explicit defaults.
        class KeywordReader
          def initialize(options)
            @options = options
          end

          def keys = options.keys
          def token_generator = fetch(:token_generator, -> { SecureRandom.uuid })
          def expired_tombstone_limit = fetch(:expired_tombstone_limit, DEFAULT_EXPIRED_TOMBSTONE_LIMIT)

          def completed_batch_retention_limit
            fetch(:completed_batch_retention_limit, DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT)
          end

          def max_batch_size = fetch(:max_batch_size, DEFAULT_MAX_BATCH_SIZE)
          def policy_set = fetch(:policy_set, Backpressure::PolicySet.new)
          def circuit_breaker_policy_set = fetch(:circuit_breaker_policy_set, CircuitBreaker::PolicySet.new)
          def fairness_policy = fetch(:fairness_policy, Fairness::Policy.new)

          private

          attr_reader :options

          def fetch(name, default)
            options.fetch(name, default)
          end
        end

        # Validates unknown keyword options.
        class UnknownKeywords
          def initialize(keys)
            @keys = keys
          end

          def validate
            raise ArgumentError, "unknown keywords: #{unexpected_keys.join(', ')}" unless unexpected_keys.empty?
          end

          private

          attr_reader :keys

          def unexpected_keys
            keys - VALID_KEYS
          end
        end

        VALID_KEYS = %i[
          token_generator
          expired_tombstone_limit
          completed_batch_retention_limit
          max_batch_size
          policy_set
          circuit_breaker_policy_set
          fairness_policy
        ].freeze

        def initialize(options)
          @reader = KeywordReader.new(options)
          UnknownKeywords.new(reader.keys).validate
        end

        def token_generator = reader.token_generator
        def expired_tombstone_limit = reader.expired_tombstone_limit
        def completed_batch_retention_limit = reader.completed_batch_retention_limit
        def max_batch_size = reader.max_batch_size
        def policy_set = reader.policy_set
        def circuit_breaker_policy_set = reader.circuit_breaker_policy_set
        def fairness_policy = reader.fairness_policy

        private

        attr_reader :reader

        private_constant :KeywordReader, :UnknownKeywords
      end

      def initialize(**options)
        initializer_options = InitializerOptions.new(options)
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
        @completed_batch_retention_limit = completed_batch_retention_limit
        @max_batch_size = max_batch_size
        @policy_set = policy_set
        @circuit_breaker_policy_set = circuit_breaker_policy_set
        @fairness_policy = fairness_policy
        @reservation_token_sequence = 0
        @mutex = Mutex.new
        @state = Internal::StoreState.new(expired_tombstone_limit:)
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

        @mutex.synchronize { reserve_matching_job(**reserve_request) }
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

      # Inspection helper exposed only by QueueStore::InMemory.
      # It is not part of QueueStore::Base, and other queue-store backends are
      # not expected to implement it. Callers that need backend-portable queue
      # store behavior must not rely on this API.
      def backpressure_snapshot(now:)
        normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

        @mutex.synchronize do
          prepare_backpressure_snapshot(normalized_now)
          build_backpressure_snapshot(normalized_now)
        end
      end

      # Inspection helper exposed only by QueueStore::InMemory.
      # It is not part of QueueStore::Base, and other queue-store backends are
      # not expected to implement it. Callers that need backend-portable queue
      # store behavior must not rely on this API.
      def reliability_snapshot(now:)
        normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

        @mutex.synchronize do
          prepare_reliability_snapshot(normalized_now)
          build_reliability_snapshot(normalized_now)
        end
      end

      # Inspection helper exposed only by QueueStore::InMemory.
      # It is not part of QueueStore::Base, and other queue-store backends are
      # not expected to implement it. Callers that need backend-portable queue
      # store behavior must not rely on this API.
      def uniqueness_decision(job:, now:)
        normalized_now = normalize_time(:now, now, error_class: InvalidEnqueueError)

        @mutex.synchronize do
          validate_enqueue(job)
          build_uniqueness_decision(job, normalized_now)
        end
      end

      # Inspection helper exposed only by QueueStore::InMemory.
      # It is not part of QueueStore::Base, and other queue-store backends are
      # not expected to implement it. Callers that need backend-portable queue
      # store behavior must not rely on this API.
      def uniqueness_snapshot(now:)
        normalized_now = normalize_time(:now, now, error_class: InvalidQueueStoreOperationError)

        @mutex.synchronize do
          build_uniqueness_snapshot(normalized_now)
        end
      end

      private

      attr_reader :circuit_breaker_policy_set,
                  :completed_batch_retention_limit,
                  :fairness_policy,
                  :max_batch_size,
                  :policy_set,
                  :state,
                  :token_generator

      private_constant :InitializerOptions, :Internal

      def validate_initializer_limits(expired_tombstone_limit:, completed_batch_retention_limit:, max_batch_size:)
        valid_tombstone_limit = expired_tombstone_limit.is_a?(Integer) && expired_tombstone_limit >= 0
        raise InvalidQueueStoreOperationError, 'expired_tombstone_limit must be a finite non-negative Integer' unless valid_tombstone_limit

        valid_batch_retention_limit = completed_batch_retention_limit.is_a?(Integer) &&
                                      completed_batch_retention_limit >= 0
        raise InvalidQueueStoreOperationError, 'completed_batch_retention_limit must be a finite non-negative Integer' unless valid_batch_retention_limit

        return if max_batch_size.is_a?(Integer) && max_batch_size.positive?

        raise InvalidQueueStoreOperationError, 'max_batch_size must be a positive Integer'
      end

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
        prune_stale_rate_limit_admissions(now)
        nil
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

      def store_and_requeue_if_needed(job)
        store_job(job:)
        state.queue_job_ids_for(job.queue) << job.id if job.state == :queued
        job
      end

      def reserve_matching_job(handler_matcher:, lease_duration:, now:, queues:, subscription_key:, worker_id:)
        reserve_scan_state = perform_reserve_maintenance(now)
        matched_queue, matched_job_index, matched_job_id =
          find_reserved_job(
            queues,
            subscription_key,
            handler_matcher,
            reserve_scan_state,
            now
          )
        return nil unless matched_job_id

        reserve_job(
          matched_queue:,
          matched_job_id:,
          matched_job_index:,
          lease_duration:,
          now:,
          queues:,
          subscription_key:,
          worker_id:
        )
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
