# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module RuntimeSupport
      # Shared max-iteration normalization used by worker and supervisor runtime support.
      class IterationLimit
        def initialize(value, error_class:, unlimited_sentinel: :unlimited)
          @error_class = error_class
          @unlimited_sentinel = unlimited_sentinel
          @value = value
          @normalized_value = normalize_value
        end

        def normalize
          normalized_value
        end

        def reached?(iterations)
          return false if normalized_value == unlimited_sentinel

          iterations >= normalized_value
        end

        private

        attr_reader :error_class, :normalized_value, :unlimited_sentinel, :value

        def normalize_value
          return unlimited_sentinel if value.is_a?(NilClass)
          return value if value.is_a?(Integer) && value.positive?

          raise_invalid_iteration_limit
        end

        def raise_invalid_iteration_limit
          raise error_class, 'max_iterations must be a positive Integer'
        end
      end
    end
  end
end
