# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Reservation
    # Normalizes timestamps into frozen copies so reservations stay immutable.
    class TimestampNormalizer
      def initialize(name, value)
        @name = name
        @value = value
      end

      def normalize
        return value.dup.freeze if value.is_a?(Time)

        raise InvalidReservationAttributeError, "#{name} must be a Time"
      end

      private

      attr_reader :name, :value
    end
  end
end
