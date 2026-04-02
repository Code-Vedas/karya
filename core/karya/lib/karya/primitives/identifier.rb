# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Primitives
    # Validates identifier-like values into non-blank strings.
    class Identifier
      def initialize(name, value, error_class:)
        @name = name
        @value = value
        @error_class = error_class
      end

      def normalize
        normalized_value = value.to_s.strip
        return normalized_value.freeze unless normalized_value.empty?

        raise error_class, "#{name} must be present"
      end

      private

      attr_reader :name, :value, :error_class
    end
  end
end
