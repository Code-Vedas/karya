# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../base'
require_relative '../backend'
require_relative '../backpressure'
require_relative '../circuit_breaker'
require_relative '../fairness'
require_relative '../queue_store/postgres'

module Karya
  module Backend
    # Postgres-backed backend wrapper for durable queue-store boot.
    class Postgres
      include Base

      def initialize(url:, namespace: QueueStore::Postgres::DEFAULT_NAMESPACE, **queue_store_options)
        @identifier = 'postgres'
        @queue_store_options = {
          url:,
          namespace:,
          **queue_store_options
        }.freeze
      end

      attr_reader :identifier

      def build_queue_store
        QueueStore::Postgres.new(**queue_store_options)
      rescue ArgumentError, TypeError, InvalidQueueStoreOperationError => e
        raise InvalidBackendConfigurationError, "#{queue_store_configuration_error_message}: #{e.message}", cause: e
      end

      private

      attr_reader :queue_store_options

      def queue_store_configuration_error_message
        invalid_keys = queue_store_options.keys - valid_queue_store_option_keys
        return "invalid Postgres backend queue-store configuration: unexpected option keys #{invalid_keys.map(&:inspect).join(', ')}" unless invalid_keys.empty?

        'invalid Postgres backend queue-store configuration'
      end

      def valid_queue_store_option_keys
        %i[
          url
          namespace
          expired_tombstone_limit
          completed_batch_retention_limit
          max_batch_size
          policy_set
          circuit_breaker_policy_set
          fairness_policy
        ]
      end
    end
  end
end
