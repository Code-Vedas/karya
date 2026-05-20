# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require 'uri'

require_relative 'internal/reference_queue_store'
require_relative 'sqlite/internal'

module Karya
  module QueueStore
    # SQLite-backed local durable queue store that persists canonical queue state in SQLite.
    class SQLite
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

      # Normalizes required non-empty SQLite string configuration values.
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

      # Parses a SQLite file URL into a local filesystem path.
      class ConnectionPath
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
          host = normalize_string(uri.host)
          uri_path = uri.path.to_s
          raw_path = if host && host != 'localhost'
                       File.join(host, uri_path.sub(%r{\A/+}, ''))
                     else
                       uri_path
                     end
          path = URI::DEFAULT_PARSER.unescape(raw_path)
          raise InvalidQueueStoreOperationError, 'url must include a durable SQLite file path' if ['', '/', ':memory:', '/:memory:'].include?(path)

          path
        rescue URI::InvalidURIError, ArgumentError => e
          raise InvalidQueueStoreOperationError, "invalid SQLite url: #{e.message}", cause: e
        end

        private

        attr_reader :present_string_class, :url

        def normalize_string(value)
          present_string_class.new(value).normalize
        end

        def validate_scheme(uri)
          return if %w[sqlite sqlite3].include?(uri.scheme)

          raise InvalidQueueStoreOperationError, 'url must use sqlite:// or sqlite3://'
        end
      end

      # Builds configured SQLite connections for the queue store.
      class ConnectionBuilder
        def self.build(path)
          database = SQLite3::Database.new(path)
          database.results_as_hash = true
          begin
            database.busy_timeout = 5000
          rescue NoMethodError
            nil
          end
          database
        end
      end

      def initialize(url:, namespace: DEFAULT_NAMESPACE, **options)
        raise InvalidQueueStoreOperationError, 'token_generator is managed internally by Karya::QueueStore::SQLite' if options.key?(:token_generator)

        Internal::DependencyLoader.require_sqlite3!
        @url = normalize_url(url)
        @namespace = normalize_namespace(namespace)
        @connection_path = ConnectionPath.build(url: @url, present_string_class: PresentString)
        @connection = build_connection
        @connection_pid = Process.pid
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

      attr_reader :mutex, :namespace, :persistence_mutex, :reservation_token_sequence, :url

      def connection
        reconnect_if_forked
        @connection
      end

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

      attr_reader :connection_path, :state

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

      def reconnect_if_forked
        current_pid = Process.pid
        return if @connection_pid == current_pid

        @connection&.close
        @connection = build_connection
        @connection_pid = current_pid
        nil
      rescue StandardError
        @connection = nil
        raise
      end

      def build_connection
        ConnectionBuilder.build(connection_path)
      end
    end
  end
end
