# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Primitives
    # Validates positive integer values.
    class PositiveInteger
      def initialize(name, value, error_class:)
        @name = name
        @value = value
        @error_class = error_class
      end

      def normalize
        return value if value.is_a?(Integer) && value.positive?

        raise error_class, "#{name} must be a positive Integer"
      end

      private

      attr_reader :name, :value, :error_class
    end
  end
end
