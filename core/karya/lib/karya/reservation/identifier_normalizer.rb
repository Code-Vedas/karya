# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Reservation
    # Normalizes identifier-like attributes into frozen, non-blank strings.
    class IdentifierNormalizer
      def initialize(name, value)
        @name = name
        @value = value
      end

      def normalize
        normalized_value = value.to_s.strip
        return normalized_value.freeze unless normalized_value.empty?

        raise InvalidReservationAttributeError, "#{name} must be present"
      end

      private

      attr_reader :name, :value
    end
  end
end
