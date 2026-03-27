# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'base'

module Karya
  # Raised when reservation attributes are invalid.
  class InvalidReservationAttributeError < Error; end

  # Immutable value object representing a temporary lease on a queued job.
  class Reservation
    attr_reader :expires_at, :job_id, :queue, :reserved_at, :token, :worker_id

    def initialize(**attributes)
      normalized_attributes = Attributes.new(attributes).to_h

      @token = normalized_attributes.fetch(:token)
      @job_id = normalized_attributes.fetch(:job_id)
      @queue = normalized_attributes.fetch(:queue)
      @worker_id = normalized_attributes.fetch(:worker_id)
      @reserved_at = normalized_attributes.fetch(:reserved_at)
      @expires_at = normalized_attributes.fetch(:expires_at)

      freeze
    end

    def expired?(now)
      current_time = Attributes::TimestampNormalizer.new(:now, now).normalize
      expires_at <= current_time
    end

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

      private

      attr_reader :attributes

      def required(name)
        attributes.fetch(name)
      rescue KeyError
        raise InvalidReservationAttributeError, "#{name} must be present"
      end
    end

    private_constant :Attributes
  end
end
