# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class Redis < InMemory
      module Internal
        # Marshals the durable queue-store state payload stored in Redis.
        module StateSnapshot
          # Owner-local Marshal wrapper for Redis persistence payloads.
          module MarshalCodec
            module_function

            def dump(payload)
              Marshal.dump(payload)
            end

            def load(payload)
              Marshal.method(:load).call(payload)
            end
          end
          private_constant :MarshalCodec

          module_function

          def dump(state:, reservation_token_sequence:)
            MarshalCodec.dump(
              state:,
              reservation_token_sequence:
            )
          end

          def load(payload)
            MarshalCodec.load(payload)
          end
        end
      end
    end
  end
end
