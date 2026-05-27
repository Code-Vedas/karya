# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Primitives
    # Validates positive, finite numeric values.
    class PositiveFiniteNumber
      def initialize(name, value, error_class:)
        @name = name
        @value = value
        @error_class = error_class
      end

      def normalize
        return value if valid?

        raise error_class, "#{name} must be a positive finite number"
      end

      private

      attr_reader :name, :value, :error_class

      def valid?
        value.is_a?(Numeric) && value.positive? && (!value.is_a?(Float) || value.finite?)
      end
    end
  end
end
