# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

require_relative '../job'
require_relative '../internal/durable_queue_store'
require_relative 'postgres/internal'

module Karya
  module QueueStore
    # Postgres-backed durable queue store that persists canonical queue state in Postgres.
    class Postgres
      include Karya::Internal::DurableQueueStore::PersistedAdapter

      DEFAULT_NAMESPACE = 'karya'
      DEFAULT_EXPIRED_TOMBSTONE_LIMIT = Karya::Internal::DurableQueueStore::PersistedAdapter::DEFAULT_EXPIRED_TOMBSTONE_LIMIT
      DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT = Karya::Internal::DurableQueueStore::PersistedAdapter::DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT
      DEFAULT_MAX_BATCH_SIZE = Karya::Internal::DurableQueueStore::PersistedAdapter::DEFAULT_MAX_BATCH_SIZE
      RESERVE_QUEUES_ERROR_MESSAGE = Karya::Internal::DurableQueueStore::PersistedAdapter::RESERVE_QUEUES_ERROR_MESSAGE

      # Normalizes required non-empty Postgres string configuration values.
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
        raise InvalidQueueStoreOperationError, 'token_generator is managed internally by Karya::QueueStore::Postgres' if options.key?(:token_generator)

        Internal::DependencyLoader.require_pg!
        @url = normalize_url(url)
        @namespace = normalize_namespace(namespace)
        @connection = PG.connect(@url)
        configure_connection_type_maps
        configure_persisted_queue_store(
          initializer_options_class: Karya::QueueStore::Internal::InitializerOptions,
          token_generator: -> { SecureRandom.uuid },
          **options
        )
        @persistence_mutex = Internal::PersistenceMutex.new(connection:, owner: self)
        @mutex = @persistence_mutex
        @persistence_mutex.ensure_schema
      rescue StandardError
        @connection&.close
        raise
      end

      attr_reader :connection, :mutex, :namespace, :persistence_mutex, :url

      private

      def configure_connection_type_maps
        return unless defined?(PG::BasicTypeMapForResults)

        connection.type_map_for_results = PG::BasicTypeMapForResults.new(connection)
        nil
      rescue NoMethodError, TypeError
        nil
      end

      def normalize_url(value)
        normalized = PresentString.new(value).normalize
        return normalized if normalized

        raise InvalidQueueStoreOperationError, 'url must be a non-empty String'
      end

      def normalize_namespace(value)
        normalized = PresentString.new(value).normalize
        return normalized if normalized

        raise InvalidQueueStoreOperationError, 'namespace must be a non-empty String'
      end
    end
  end
end
