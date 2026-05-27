# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Wraps one persisted policy-state row and decodes its durable payload.
        class PolicyStateRow
          def initialize(row:)
            @row = row
          end

          attr_reader :row

          def payload(default: {})
            return default unless row

            encoded_payload = row[:state_payload]
            encoded_payload ? (PayloadCodec.decode(encoded_payload) || default) : default
          end
        end
      end
    end
  end
end
