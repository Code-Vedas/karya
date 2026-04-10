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
          when Integer, Rational
            positive_rational_or_integer?
          when Float, BigDecimal
            positive_finite_float_or_decimal?
          else
            false
          end
        end

        def positive_rational_or_integer?
          value.positive?
        end

        def positive_finite_float_or_decimal?
          value.positive? && value.finite?
        end
      end
    end
  end
end
