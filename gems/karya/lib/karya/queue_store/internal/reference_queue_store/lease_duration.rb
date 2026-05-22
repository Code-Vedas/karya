# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'bigdecimal'
require_relative '../../../base'
require_relative '../../../queue_store'

module Karya
  module QueueStore
    module Internal
      module ReferenceQueueStore
        module Internal
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
              return false unless numeric_duration?

              positive_value = value.positive?
              return positive_value unless finite_numeric_duration?

              positive_value && value.finite?
            end

            def numeric_duration?
              value.is_a?(Integer) || value.is_a?(Rational) || finite_numeric_duration?
            end

            def finite_numeric_duration?
              value.is_a?(Float) || value.is_a?(BigDecimal)
            end
          end
        end
      end
    end
  end
end
