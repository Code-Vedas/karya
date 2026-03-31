# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Job
    # Normalizes constructor input without leaking validation helpers onto the public job API.
    class Attributes
      def initialize(attributes)
        @attributes = attributes
      end

      def to_h
        created_at = TimestampNormalizer.new(:created_at, required(:created_at)).normalize
        attempt = optional(:attempt, 0)
        lifecycle = optional(:lifecycle, JobLifecycle.default_registry)
        raise InvalidJobAttributeError, 'attempt must be a non-negative Integer' unless attempt.is_a?(Integer) && attempt >= 0

        {
          id: IdentifierNormalizer.new(:id, required(:id)).normalize,
          queue: IdentifierNormalizer.new(:queue, required(:queue)).normalize,
          handler: IdentifierNormalizer.new(:handler, required(:handler)).normalize,
          arguments: ImmutableArguments.new(optional(:arguments, {})).normalize,
          lifecycle:,
          state: lifecycle.normalize_state(required(:state)),
          attempt:,
          created_at:,
          updated_at: TimestampNormalizer.new(:updated_at, optional(:updated_at, created_at)).normalize
        }
      end

      private

      attr_reader :attributes

      def required(name)
        attributes.fetch(name)
      rescue KeyError
        raise InvalidJobAttributeError, "#{name} must be present"
      end

      def optional(name, default)
        attributes.fetch(name, default)
      end

      # Normalizes required identifier-like fields into frozen, non-blank strings.
      class IdentifierNormalizer
        def initialize(name, value)
          @name = name
          @value = value
        end

        def normalize
          normalized_value = value.to_s.strip
          return normalized_value.freeze unless normalized_value.empty?

          raise InvalidJobAttributeError, "#{name} must be present"
        end

        private

        attr_reader :name, :value
      end

      # Normalizes timestamps into frozen copies so jobs cannot mutate caller-owned Time objects.
      class TimestampNormalizer
        def initialize(name, value)
          @name = name
          @value = value
        end

        def normalize
          return value.dup.freeze if value.is_a?(Time)

          raise InvalidJobAttributeError, "#{name} must be a Time"
        end

        private

        attr_reader :name, :value
      end

      private_constant :IdentifierNormalizer, :TimestampNormalizer
    end
  end
end
