# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../primitives/lifecycle'

module Karya
  class Job
    # Normalizes constructor input without leaking validation helpers onto the public job API.
    class Attributes
      def initialize(attributes)
        @attributes = attributes
      end

      def to_h
        created_at = normalize_created_at
        lifecycle = normalize_lifecycle
        normalized_attempt = normalize_attempt
        normalized_priority = normalize_priority

        normalized_attributes(
          created_at:,
          lifecycle:,
          attempt: normalized_attempt,
          priority: normalized_priority
        )
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

      def normalized_attributes(created_at:, lifecycle:, attempt:, priority:)
        {
          id: IdentifierNormalizer.new(:id, required(:id)).normalize,
          queue: IdentifierNormalizer.new(:queue, required(:queue)).normalize,
          handler: IdentifierNormalizer.new(:handler, required(:handler)).normalize,
          arguments: ImmutableArguments.new(optional(:arguments, {})).normalize,
          priority:,
          concurrency_key: normalize_optional_identifier(:concurrency_key),
          rate_limit_key: normalize_optional_identifier(:rate_limit_key),
          lifecycle:,
          state: lifecycle.normalize_state(required(:state)),
          attempt:,
          created_at:,
          updated_at: normalize_updated_at(created_at)
        }
      end

      def normalize_attempt
        attempt = optional(:attempt, 0)
        raise InvalidJobAttributeError, 'attempt must be a non-negative Integer' unless attempt.is_a?(Integer) && attempt >= 0

        attempt
      end

      def normalize_priority
        priority = optional(:priority, 0)
        raise InvalidJobAttributeError, 'priority must be an Integer' unless priority.is_a?(Integer)

        priority
      end

      def normalize_created_at
        TimestampNormalizer.new(:created_at, required(:created_at)).normalize
      end

      def normalize_updated_at(created_at)
        TimestampNormalizer.new(:updated_at, optional(:updated_at, created_at)).normalize
      end

      def normalize_lifecycle
        Primitives::Lifecycle.new(
          :lifecycle,
          optional(:lifecycle, JobLifecycle.default_registry),
          error_class: InvalidJobAttributeError
        ).normalize
      end

      def normalize_optional_identifier(name)
        OptionalIdentifierNormalizer.new(name, optional(name, nil)).normalize
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

      # Normalizes optional identifier-like fields into frozen, non-blank strings or nil.
      class OptionalIdentifierNormalizer
        def initialize(name, value)
          @name = name
          @value = value
        end

        def normalize
          value&.then do
            normalized_value = value.to_s.strip
            return normalized_value.freeze unless normalized_value.empty?

            raise InvalidJobAttributeError, "#{name} must be present"
          end
        end

        private

        attr_reader :name, :value
      end

      private_constant :IdentifierNormalizer, :OptionalIdentifierNormalizer, :TimestampNormalizer
    end
  end
end
