# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Shared non-StoreState defaults and primitive validation helpers.
      module SharedSupport
        DEFAULT_EXPIRED_TOMBSTONE_LIMIT = 1024
        DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT = 1024
        DEFAULT_MAX_BATCH_SIZE = 1000
        RESERVE_QUEUES_ERROR_MESSAGE = 'provide exactly one of queue or queues'

        private

        def validate_initializer_limits(expired_tombstone_limit:, completed_batch_retention_limit:, max_batch_size:)
          valid_tombstone_limit = expired_tombstone_limit.is_a?(Integer) && expired_tombstone_limit >= 0
          raise InvalidQueueStoreOperationError, 'expired_tombstone_limit must be a finite non-negative Integer' unless valid_tombstone_limit

          valid_batch_retention_limit = completed_batch_retention_limit.is_a?(Integer) &&
                                        completed_batch_retention_limit >= 0
          raise InvalidQueueStoreOperationError, 'completed_batch_retention_limit must be a finite non-negative Integer' unless valid_batch_retention_limit
          return if max_batch_size.is_a?(Integer) && max_batch_size.positive?

          raise InvalidQueueStoreOperationError, 'max_batch_size must be a positive Integer'
        end

        def normalize_identifier(name, value, error_class:)
          value_class = value.class
          if value_class <= String
            Primitives::Identifier.new(name, value, error_class:).normalize
          elsif value_class <= NilClass
            raise error_class, "#{name} must be present"
          else
            raise error_class, "#{name} must be a String"
          end
        end

        def normalize_time(name, value, error_class:)
          return value if value.is_a?(Time)

          raise error_class, "#{name} must be a Time"
        end
      end
    end
  end
end
