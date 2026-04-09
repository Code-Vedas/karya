# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Validates and normalizes lease durations accepted by the queue store.
      class LeaseDuration
        def initialize(value)
          @value = value
        end

        def normalize
          raise InvalidQueueStoreOperationError, 'lease_duration must be a positive number' unless valid?

          value
        end

        private

        attr_reader :value

        def valid?
          case value
          when Integer, Float, Rational, BigDecimal
            value.positive? && (value.is_a?(Integer) || value.finite?)
          else
            false
          end
        end
      end
    end
  end
end
