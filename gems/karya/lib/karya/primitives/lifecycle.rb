# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Primitives
    # Validates lifecycle strategy objects used by jobs and runtimes.
    class Lifecycle
      REQUIRED_METHODS = %i[
        normalize_state
        validate_state!
        valid_transition?
        validate_transition!
        terminal?
      ].freeze

      def initialize(name, value, error_class:)
        @name = name
        @value = value
        @error_class = error_class
      end

      def normalize
        missing_methods = REQUIRED_METHODS - value.public_methods
        return value if missing_methods.empty?

        raise error_class,
              "#{name} must respond to #{REQUIRED_METHODS.map { |method_name| "##{method_name}" }.join(', ')}"
      end

      private

      attr_reader :error_class, :name, :value
    end
  end
end
