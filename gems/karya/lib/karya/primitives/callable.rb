# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Primitives
    # Validates callable dependencies.
    class Callable
      def initialize(name, value, error_class:)
        @name = name
        @value = value
        @error_class = error_class
      end

      def normalize
        value.public_method(:call)
        value
      rescue NameError
        raise error_class, "#{name} must respond to #call"
      end

      private

      attr_reader :name, :value, :error_class
    end
  end
end
