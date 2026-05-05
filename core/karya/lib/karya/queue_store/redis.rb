# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'redis'

require_relative 'in_memory'
require_relative 'redis/internal'

module Karya
  module QueueStore
    # Redis-backed durable queue store that persists canonical queue state in Redis.
    class Redis < InMemory
      DEFAULT_NAMESPACE = 'karya'
      DEFAULT_EXPIRED_TOMBSTONE_LIMIT = InMemory::DEFAULT_EXPIRED_TOMBSTONE_LIMIT
      DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT = InMemory::DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT
      DEFAULT_MAX_BATCH_SIZE = InMemory::DEFAULT_MAX_BATCH_SIZE

      # Normalizes required non-empty Redis string configuration values.
      class PresentString
        def initialize(value)
          @value = value
        end

        def normalize
          return unless value.is_a?(String)

          normalized_value = value.strip
          normalized_value unless normalized_value.empty?
        end

        private

        attr_reader :value
      end

      def initialize(url:, namespace: DEFAULT_NAMESPACE, **options)
        @url = normalize_url(url)
        @namespace = normalize_namespace(namespace)
        raise InvalidQueueStoreOperationError, 'token_generator is managed internally by Karya::QueueStore::Redis' if options.key?(:token_generator)

        super(**options, token_generator: -> { SecureRandom.uuid })
        @mutex = Internal::PersistenceMutex.new(
          redis: redis_client,
          owner: self,
          state_key:,
          lock_key:
        )
      end

      private

      attr_reader :namespace, :reservation_token_sequence, :url

      private_constant :PresentString

      def normalize_url(value)
        normalized_value = PresentString.new(value).normalize
        return normalized_value if normalized_value

        raise InvalidQueueStoreOperationError, 'url must be a non-empty String'
      end

      def normalize_namespace(value)
        normalized_value = PresentString.new(value).normalize
        return normalized_value if normalized_value

        raise InvalidQueueStoreOperationError, 'namespace must be a non-empty String'
      end

      def load_persisted_state
        payload = redis_client.get(state_key)
        return unless payload

        snapshot = Internal::StateSnapshot.load(payload)
        @state = snapshot.fetch(:state)
        @reservation_token_sequence = snapshot.fetch(:reservation_token_sequence)
      end

      def persist_state
        redis_client.set(
          state_key,
          Internal::StateSnapshot.dump(
            state:,
            reservation_token_sequence:
          )
        )
      end

      def redis_client
        @redis_client ||= ::Redis.new(url:)
      end

      def state_key
        "#{namespace}:queue_store:state"
      end

      def lock_key
        "#{namespace}:queue_store:lock"
      end
    end
  end
end
