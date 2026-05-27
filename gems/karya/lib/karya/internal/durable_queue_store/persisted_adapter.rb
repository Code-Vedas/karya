# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../queue_store/base'
require_relative '../../queue_store'
require_relative '../../queue_store/internal/initializer_options'

module Karya
  module Internal
    module DurableQueueStore
      # Shared public adapter for persisted queue stores.
      #
      # The snapshot-backed runtime was intentionally removed as part of the
      # hard cutover. Persisted backends remain loadable while the row-native
      # mutation engine is rebuilt.
      module PersistedAdapter
        include Karya::QueueStore::Base
        include SharedSupport

        DEFAULT_EXPIRED_TOMBSTONE_LIMIT = SharedSupport::DEFAULT_EXPIRED_TOMBSTONE_LIMIT
        DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT = SharedSupport::DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT
        DEFAULT_MAX_BATCH_SIZE = SharedSupport::DEFAULT_MAX_BATCH_SIZE
        RESERVE_QUEUES_ERROR_MESSAGE = SharedSupport::RESERVE_QUEUES_ERROR_MESSAGE

        def configure_persisted_queue_store(initializer_options_class:, **options)
          initializer_options = initializer_options_class.new(options)
          expired_tombstone_limit = initializer_options.expired_tombstone_limit
          completed_batch_retention_limit = initializer_options.completed_batch_retention_limit
          max_batch_size = initializer_options.max_batch_size
          token_generator = initializer_options.token_generator
          policy_set = initializer_options.policy_set
          circuit_breaker_policy_set = initializer_options.circuit_breaker_policy_set
          fairness_policy = initializer_options.fairness_policy

          validation_support.send(
            :validate_initializer_limits,
            expired_tombstone_limit:,
            completed_batch_retention_limit:,
            max_batch_size:
          )
          Karya::Primitives::Callable.new(
            :token_generator,
            token_generator,
            error_class: Karya::InvalidQueueStoreOperationError
          ).normalize
          unless policy_set.is_a?(Karya::Backpressure::PolicySet)
            raise Karya::InvalidQueueStoreOperationError, 'policy_set must be a Karya::Backpressure::PolicySet'
          end
          unless fairness_policy.is_a?(Karya::Fairness::Policy)
            raise Karya::InvalidQueueStoreOperationError, 'fairness_policy must be a Karya::Fairness::Policy'
          end
          unless circuit_breaker_policy_set.is_a?(Karya::CircuitBreaker::PolicySet)
            raise Karya::InvalidQueueStoreOperationError,
                  'circuit_breaker_policy_set must be a Karya::CircuitBreaker::PolicySet'
          end

          @token_generator = token_generator
          @expired_tombstone_limit = expired_tombstone_limit
          @completed_batch_retention_limit = completed_batch_retention_limit
          @max_batch_size = max_batch_size
          @policy_set = policy_set
          @circuit_breaker_policy_set = circuit_breaker_policy_set
          @fairness_policy = fairness_policy
        end

        Karya::QueueStore::Base.instance_methods(false).each do |method_name|
          define_method(method_name) do |*args, **kwargs|
            execute_persisted_operation(method_name, args, kwargs)
          end
        end

        def uniqueness_decision(job:, now:)
          execute_persisted_operation(__method__, [], { job:, now: })
        end

        def uniqueness_snapshot(now:)
          execute_persisted_operation(__method__, [], { now: })
        end

        def backpressure_snapshot(now:)
          execute_persisted_operation(__method__, [], { now: })
        end

        def reliability_snapshot(now:)
          execute_persisted_operation(__method__, [], { now: })
        end

        private

        attr_reader :circuit_breaker_policy_set,
                    :completed_batch_retention_limit,
                    :expired_tombstone_limit,
                    :fairness_policy,
                    :max_batch_size,
                    :policy_set,
                    :token_generator

        def validation_support = self

        def durable_state_store
          instance_variable_get(:@durable_state_store) || persistence_mutex.send(:durable_state_store)
        end

        def persisted_engine
          @persisted_engine ||= Engine.new(store: self)
        end

        def execute_persisted_operation(method_name, args, kwargs)
          raise ArgumentError, 'positional arguments are not supported for persisted queue-store operations' unless args.empty?

          persisted_engine.execute(operation_name: method_name, request: kwargs)
        end
      end
    end
  end
end
