# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class MySQL
      module Internal
        # Encodes the durable queue-store state payload stored in MySQL.
        module StateCodec
          module_function

          def dump(state:, reservation_token_sequence:)
            [
              Marshal.dump(
                {
                  state:,
                  reservation_token_sequence:
                }
              )
            ].pack('m0')
          end

          def load(payload)
            # The payload is produced internally by `dump` and never accepted
            # from user input or external network callers.
            # rubocop:disable Security/MarshalLoad
            snapshot = Marshal.load(payload.unpack1('m0'))
            # rubocop:enable Security/MarshalLoad
            validate_snapshot(snapshot)
          rescue ArgumentError, TypeError => e
            raise InvalidQueueStoreOperationError, "invalid MySQL state snapshot: #{e.class}: #{e.message}", cause: e
          end

          def validate_snapshot(snapshot)
            unless snapshot.is_a?(Hash) &&
                   snapshot.fetch(:state).is_a?(Karya::QueueStore::Internal::StoreState) &&
                   snapshot.fetch(:reservation_token_sequence).is_a?(Integer)
              raise InvalidQueueStoreOperationError, 'invalid MySQL state snapshot payload'
            end

            snapshot
          rescue KeyError => e
            raise InvalidQueueStoreOperationError, "invalid MySQL state snapshot: #{e.message}", cause: e
          end
        end
      end
    end
  end
end
