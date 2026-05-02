# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../base'
require_relative '../backend'
require_relative '../queue_store/in_memory'

module Karya
  module Backend
    # Quick-start backend wrapper around the single-process reference queue store.
    class InMemory
      include Base

      UNSET = Object.new.freeze
      private_constant :UNSET

      def initialize(queue_store_class: QueueStore::InMemory)
        @identifier = 'in_memory'
        @queue_store_class = queue_store_class
      end

      attr_reader :identifier

      def build_queue_store(
        token_generator: UNSET,
        expired_tombstone_limit: UNSET,
        completed_batch_retention_limit: UNSET,
        max_batch_size: UNSET,
        policy_set: UNSET,
        circuit_breaker_policy_set: UNSET,
        fairness_policy: UNSET
      )
        queue_store = queue_store_class.new(**{
          token_generator:,
          expired_tombstone_limit:,
          completed_batch_retention_limit:,
          max_batch_size:,
          policy_set:,
          circuit_breaker_policy_set:,
          fairness_policy:
        }.reject { |_name, value| value.equal?(UNSET) })
        return queue_store if queue_store.is_a?(QueueStore::Base)

        raise InvalidBackendConfigurationError, 'queue_store_class must build a Karya::QueueStore::Base'
      end

      def before_start(queue_store:)
        _queue_store = queue_store
        nil
      end

      def after_stop(queue_store:)
        _queue_store = queue_store
        nil
      end

      private

      attr_reader :queue_store_class
    end
  end
end
