# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class CLI < Thor
    # Coerces CLI option values into positive Integers with consistent errors.
    class IntegerOption
      def initialize(name, value)
        @name = name
        @value = value
      end

      def normalize
        normalized = coerce
        return normalized if normalized.positive?

        raise_invalid_value
      rescue ArgumentError, TypeError
        raise_invalid_value
      end

      private

      attr_reader :name, :value

      def coerce
        return value if value.is_a?(Integer)
        return float_to_integer if value.is_a?(Float)

        Integer(value, 10)
      end

      def error_message
        "Invalid value for --#{name.to_s.tr('_', '-')}: #{value.inspect}. Expected a positive integer."
      end

      def float_to_integer
        integer_value = value.to_i
        raise_invalid_value unless value.finite? && value == integer_value

        integer_value
      end

      def raise_invalid_value
        raise InvalidWorkerSupervisorConfigurationError, error_message
      end
    end
  end
end
