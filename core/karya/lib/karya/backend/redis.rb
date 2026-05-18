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
require_relative '../queue_store/redis'

module Karya
  module Backend
    # Redis-backed backend wrapper for durable queue-store boot.
    class Redis
      include Base

      def initialize(url:, namespace: QueueStore::Redis::DEFAULT_NAMESPACE, **queue_store_options)
        @identifier = 'redis'
        @queue_store_options = {
          url:,
          namespace:,
          **queue_store_options
        }.freeze
      end

      attr_reader :identifier

      def build_queue_store
        QueueStore::Redis.new(**queue_store_options)
      rescue ArgumentError, TypeError, InvalidQueueStoreOperationError => e
        raise InvalidBackendConfigurationError, "#{queue_store_configuration_error_message}: #{e.message}", cause: e
      end

      private

      attr_reader :queue_store_options

      def queue_store_configuration_error_message
        invalid_keys = queue_store_options.keys - valid_queue_store_option_keys
        return "invalid Redis backend queue-store configuration: unexpected option keys #{invalid_keys.map(&:inspect).join(', ')}" unless invalid_keys.empty?

        'invalid Redis backend queue-store configuration'
      end

      def valid_queue_store_option_keys
        %i[
          url
          namespace
          max_batch_size
          expired_tombstone_limit
          completed_batch_retention_limit
          policy_set
          circuit_breaker_policy_set
          fairness_policy
        ]
      end
    end
  end
end
