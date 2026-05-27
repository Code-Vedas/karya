# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require 'uri'

require_relative '../job'
require_relative '../internal/durable_queue_store'
require_relative 'sqlite/internal'

module Karya
  module QueueStore
    # SQLite-backed local durable queue store that persists canonical queue state in SQLite.
    class SQLite
      include Karya::Internal::DurableQueueStore::PersistedAdapter

      DEFAULT_NAMESPACE = 'karya'
      DEFAULT_EXPIRED_TOMBSTONE_LIMIT = Karya::Internal::DurableQueueStore::PersistedAdapter::DEFAULT_EXPIRED_TOMBSTONE_LIMIT
      DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT = Karya::Internal::DurableQueueStore::PersistedAdapter::DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT
      DEFAULT_MAX_BATCH_SIZE = Karya::Internal::DurableQueueStore::PersistedAdapter::DEFAULT_MAX_BATCH_SIZE
      RESERVE_QUEUES_ERROR_MESSAGE = Karya::Internal::DurableQueueStore::PersistedAdapter::RESERVE_QUEUES_ERROR_MESSAGE

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

      attr_reader :namespace, :url

      def connection
        reconnect_if_needed
        @connection
      end

      def mutex
        persistence_mutex
      end

      def persistence_mutex
        reconnect_if_needed
        @persistence_mutex
      end

      private

      attr_reader :connection_path

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

      def reconnect_if_needed
        current_pid = Process.pid
        return if @connection_pid == current_pid && @connection

        @connection&.close
        @connection = build_connection
        @connection_pid = current_pid
        @persistence_mutex = build_persistence_mutex(@connection)
        @mutex = @persistence_mutex
        nil
      rescue StandardError
        @connection = nil
        @persistence_mutex = nil
        @mutex = nil
        raise
      end

      def build_connection
        wrap_connection_close(ConnectionBuilder.build(connection_path))
      end

      def build_persistence_mutex(database)
        Internal::PersistenceMutex.new(connection: database, owner: self)
      end

      def wrap_connection_close(database)
        original_close = database.method(:close)
        owner = self
        database.define_singleton_method(:close) do
          original_close.call
          owner.send(:clear_connection_reference, self)
          nil
        end
        database
      rescue NameError
        database
      end

      def clear_connection_reference(database)
        return unless @connection.equal?(database)

        @connection = nil
        @connection_pid = nil
        nil
      end

      def disconnect_for_fork
        @connection&.close
        @connection = nil
        @connection_pid = nil
        @persistence_mutex = nil
        @mutex = nil
        nil
      end
    end
  end
end
