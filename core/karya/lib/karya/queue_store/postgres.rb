# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

require_relative 'internal/reference_queue_store'
require_relative 'postgres/internal'

module Karya
  module QueueStore
    # Postgres-backed durable queue store that persists canonical queue state in Postgres.
    class Postgres
      include Karya::QueueStore::Internal::ReferenceQueueStore

      module Internal
        StoreState = Karya::QueueStore::Internal::StoreState
      end

      DEFAULT_NAMESPACE = 'karya'
      DEFAULT_EXPIRED_TOMBSTONE_LIMIT = Karya::QueueStore::Internal::ReferenceQueueStore::DEFAULT_EXPIRED_TOMBSTONE_LIMIT
      DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT = Karya::QueueStore::Internal::ReferenceQueueStore::DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT
      DEFAULT_MAX_BATCH_SIZE = Karya::QueueStore::Internal::ReferenceQueueStore::DEFAULT_MAX_BATCH_SIZE
      RESERVE_QUEUES_ERROR_MESSAGE = Karya::QueueStore::Internal::ReferenceQueueStore::RESERVE_QUEUES_ERROR_MESSAGE
      private_constant :Internal

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
        configure_reference_queue_store(
          initializer_options_class: Karya::QueueStore::Internal::InitializerOptions,
          store_state_class: Internal::StoreState,
          token_generator: -> { SecureRandom.uuid },
          **options
        )
        @persistence_mutex = Internal::PersistenceMutex.new(connection:, owner: self)
        @mutex = @persistence_mutex
        @persistence_mutex.ensure_schema
        load_persisted_state
      end

      attr_reader :connection, :mutex, :namespace, :persistence_mutex, :reservation_token_sequence, :url

      def load_persisted_state
        restore_state_snapshot(persistence_mutex.load_state_snapshot)
      end

      def dump_state_payload
        Internal::StateCodec.dump(
          state:,
          reservation_token_sequence:
        )
      end

      def restore_authoritative_state_after_failure
        load_persisted_state
        nil
      rescue StandardError
        nil
      end

      private

      attr_reader :state

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

      def restore_state_snapshot(snapshot)
        if snapshot
          @state = snapshot.fetch(:state)
          @reservation_token_sequence = snapshot.fetch(:reservation_token_sequence)
        else
          @state = Internal::StoreState.new(expired_tombstone_limit:)
          @reservation_token_sequence = 0
        end
      end
    end
  end
end
