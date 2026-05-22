# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

require_relative '../job'
require_relative '../internal/durable_queue_store'
require_relative 'redis/internal/dependency_loader'
require_relative 'redis/internal'

Karya::QueueStore::Redis::Internal::DependencyLoader.require_redis!

module Karya
  module QueueStore
    # Redis-backed durable queue store that persists canonical queue state in Redis.
    class Redis
      include Karya::Internal::DurableQueueStore::PersistedAdapter

      DEFAULT_NAMESPACE = 'karya'
      DEFAULT_EXPIRED_TOMBSTONE_LIMIT = Karya::Internal::DurableQueueStore::PersistedAdapter::DEFAULT_EXPIRED_TOMBSTONE_LIMIT
      DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT = Karya::Internal::DurableQueueStore::PersistedAdapter::DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT
      DEFAULT_MAX_BATCH_SIZE = Karya::Internal::DurableQueueStore::PersistedAdapter::DEFAULT_MAX_BATCH_SIZE
      RESERVE_QUEUES_ERROR_MESSAGE = Karya::Internal::DurableQueueStore::PersistedAdapter::RESERVE_QUEUES_ERROR_MESSAGE

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

        configure_persisted_queue_store(
          initializer_options_class: Karya::QueueStore::Internal::InitializerOptions,
          **options,
          token_generator: -> { SecureRandom.uuid }
        )
        @durable_state_store = Internal::DurableStateStore.new(redis: redis_client, namespace:)
        @persistence_mutex = Internal::PersistenceMutex.new(
          redis: redis_client,
          owner: self,
          durable_state_store: @durable_state_store,
          lock_key:,
          version_key:
        )
        @mutex = @persistence_mutex
      end

      attr_reader :mutex, :namespace, :persistence_mutex, :url

      private

      attr_reader :durable_state_store

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

      def redis_client
        @redis_client ||= ::Redis.new(url:)
      end

      def lock_key
        "#{namespace}:queue_store:lock"
      end

      def version_key
        "#{namespace}:queue_store:version"
      end
    end
  end
end
