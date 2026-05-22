# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../primitives/queue_list'
require_relative 'handler_matcher'
require_relative 'lease_duration'
require_relative 'shared_support'

module Karya
  module Internal
    module DurableQueueStore
      # Shared reserve request normalization helpers.
      module RequestSupport
        include SharedSupport

        private

        def normalize_reserve_queues(queue:, queues:)
          reserve_queues = queue && queues ? nil : queue || queues
          raise InvalidQueueStoreOperationError, SharedSupport::RESERVE_QUEUES_ERROR_MESSAGE unless reserve_queues

          queue_type_error_message = queue ? 'queue must be a String' : 'queues entries must be Strings'
          Array(reserve_queues).each do |value|
            raise InvalidQueueStoreOperationError, queue_type_error_message unless value.is_a?(String)
          end

          Primitives::QueueList.new(reserve_queues, error_class: InvalidQueueStoreOperationError).normalize
        end

        def normalize_reserve_request(worker_id:, lease_duration:, now:, queue:, queues:, handler_names:)
          normalized_queues = normalize_reserve_queues(queue:, queues:)
          handler_matcher = HandlerMatcher.new(handler_names)
          {
            handler_matcher:,
            lease_duration: LeaseDuration.new(lease_duration).normalize,
            now: normalize_time(:now, now, error_class: InvalidQueueStoreOperationError),
            queues: normalized_queues,
            subscription_key: [normalized_queues, handler_matcher.subscription_key_part].freeze,
            worker_id: normalize_identifier(:worker_id, worker_id, error_class: InvalidQueueStoreOperationError)
          }
        end
      end
    end
  end
end
