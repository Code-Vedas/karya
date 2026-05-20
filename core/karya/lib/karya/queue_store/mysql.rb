# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require 'uri'

require_relative 'internal/reference_queue_store'
require_relative 'mysql/internal'

module Karya
  module QueueStore
    # MySQL-backed durable queue store that persists canonical queue state in MySQL.
    class MySQL
      include Karya::QueueStore::Internal::ReferenceQueueStore

      module Internal
        StoreState = Karya::QueueStore::Internal::StoreState
      end

      DEFAULT_NAMESPACE = 'karya'
      DEFAULT_EXPIRED_TOMBSTONE_LIMIT = Karya::QueueStore::Internal::ReferenceQueueStore::DEFAULT_EXPIRED_TOMBSTONE_LIMIT
      DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT = Karya::QueueStore::Internal::ReferenceQueueStore::DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT
      DEFAULT_MAX_BATCH_SIZE = Karya::QueueStore::Internal::ReferenceQueueStore::DEFAULT_MAX_BATCH_SIZE
      MAX_NAMESPACE_CHARACTERS = 255
      RESERVE_QUEUES_ERROR_MESSAGE = Karya::QueueStore::Internal::ReferenceQueueStore::RESERVE_QUEUES_ERROR_MESSAGE
      private_constant :Internal

      # Normalizes required non-empty MySQL string configuration values.
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

      # Parses a MySQL URL into mysql2 connection options.
      class ConnectionOptions
        def self.build(url:, present_string_class:)
          new(url:, present_string_class:).build
        end

        def initialize(url:, present_string_class:)
          @url = url
          @present_string_class = present_string_class
        end

        def build
          uri = URI.parse(url)
          validate_scheme(uri)
          database_name = uri.path.to_s.delete_prefix('/')
          raise InvalidQueueStoreOperationError, 'url must include a database name' if database_name.empty?

          socket, encoding = transport_options(uri)
          options = {
            username: normalize_string(uri.user),
            password: uri.password,
            database: database_name,
            encoding:
          }.compact

          if socket
            options[:socket] = socket
          else
            options[:host] = uri.host || '127.0.0.1'
            options[:port] = uri.port || 3306
          end

          options
        rescue URI::InvalidURIError, ArgumentError => e
          raise InvalidQueueStoreOperationError, "invalid MySQL url: #{e.message}", cause: e
        end

        private

        attr_reader :present_string_class, :url

        def normalize_string(value)
          present_string_class.new(value).normalize
        end

        def transport_options(uri)
          query_options = URI.decode_www_form(uri.query.to_s).to_h
          socket = normalize_string(query_options['socket'])
          encoding = normalize_string(query_options['encoding']) || 'utf8mb4'
          [socket, encoding]
        end

        def validate_scheme(uri)
          return if %w[mysql mysql2].include?(uri.scheme)

          raise InvalidQueueStoreOperationError, 'url must use mysql:// or mysql2://'
        end
      end

      def initialize(url:, namespace: DEFAULT_NAMESPACE, **options)
        raise InvalidQueueStoreOperationError, 'token_generator is managed internally by Karya::QueueStore::MySQL' if options.key?(:token_generator)

        Internal::DependencyLoader.require_mysql2!
        @url = normalize_url(url)
        @namespace = normalize_namespace(namespace)
        @connection = Mysql2::Client.new(**ConnectionOptions.build(url: @url, present_string_class: PresentString))
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
      rescue StandardError
        @connection&.close
        raise
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
        raise InvalidQueueStoreOperationError, 'namespace must be a non-empty String' unless normalized
        return normalized if normalized.length <= MAX_NAMESPACE_CHARACTERS

        raise InvalidQueueStoreOperationError, "namespace must be at most #{MAX_NAMESPACE_CHARACTERS} characters"
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
