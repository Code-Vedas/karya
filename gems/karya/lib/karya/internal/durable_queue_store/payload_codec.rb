# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../queue_store/internal/state_snapshot'

module Karya
  module Internal
    module DurableQueueStore
      # Shared JSON payload codec for durable queue-store record columns.
      module PayloadCodec
        module_function

        def dump(value)
          Karya::QueueStore::Internal::StateSnapshot.dump_payload(value)
        end

        def dump_job_arguments(arguments)
          validate_job_argument_value!(arguments)
          dump(arguments)
        end

        def decode(payload)
          Karya::QueueStore::Internal::StateSnapshot.load_payload(payload)
        end

        def validate_job_argument_value!(value)
          case value
          when Hash
            recurse_job_argument_values(value.each_value)
          when Array
            recurse_job_argument_values(value)
          when Symbol
            raise Karya::InvalidQueueStoreOperationError,
                  'Redis queue-store snapshots do not support Symbol job arguments'
          when Float
            return if value.finite?

            raise Karya::InvalidQueueStoreOperationError,
                  'Redis queue-store snapshots do not support non-finite Float job arguments'
          end

          nil
        end

        def recurse_job_argument_values(values)
          values.each { |entry| validate_job_argument_value!(entry) }
        end
      end
    end
  end
end
