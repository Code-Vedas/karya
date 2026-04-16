# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'identifier_normalizer'
require_relative 'timestamp_normalizer'
require_relative '../primitives/identifier'

module Karya
  class Reservation
    # Normalizes and validates constructor input for immutable reservations.
    class Attributes
      def initialize(attributes)
        @attributes = attributes
      end

      def to_h
        reserved_at = TimestampNormalizer.new(:reserved_at, required(:reserved_at)).normalize
        expires_at = TimestampNormalizer.new(:expires_at, required(:expires_at)).normalize

        raise InvalidReservationAttributeError, 'expires_at must be after reserved_at' unless expires_at > reserved_at

        {
          token: IdentifierNormalizer.new(:token, required(:token)).normalize,
          job_id: IdentifierNormalizer.new(:job_id, required(:job_id)).normalize,
          queue: IdentifierNormalizer.new(:queue, required(:queue)).normalize,
          worker_id: IdentifierNormalizer.new(:worker_id, required(:worker_id)).normalize,
          reserved_at:,
          expires_at:
        }
      end

      private

      attr_reader :attributes

      def required(name)
        attributes.fetch(name)
      rescue KeyError
        raise InvalidReservationAttributeError, "#{name} must be present"
      end
    end
  end
end
