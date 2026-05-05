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
      end

      private

      attr_reader :queue_store_options
    end
  end
end
