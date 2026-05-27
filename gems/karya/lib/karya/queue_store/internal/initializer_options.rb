# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require_relative '../../base'
require_relative '../../backpressure'
require_relative '../../circuit_breaker'
require_relative '../../fairness'
require_relative '../../internal/durable_queue_store/shared_support'

module Karya
  module QueueStore
    module Internal
      # Normalizes constructor keyword options for the reference store.
      class InitializerOptions
        # Reads constructor keyword options with explicit defaults.
        class KeywordReader
          def initialize(options)
            @options = options
          end

          def keys = options.keys
          def token_generator = fetch(:token_generator, -> { SecureRandom.uuid })
          def expired_tombstone_limit = fetch(:expired_tombstone_limit, Karya::Internal::DurableQueueStore::SharedSupport::DEFAULT_EXPIRED_TOMBSTONE_LIMIT)

          def completed_batch_retention_limit
            fetch(
              :completed_batch_retention_limit,
              Karya::Internal::DurableQueueStore::SharedSupport::DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT
            )
          end

          def max_batch_size = fetch(:max_batch_size, Karya::Internal::DurableQueueStore::SharedSupport::DEFAULT_MAX_BATCH_SIZE)
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
    end
  end
end
