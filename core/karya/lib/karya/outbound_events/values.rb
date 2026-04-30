# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module OutboundEvents
    # Normalizes required string-like values.
    class PresentString
      def initialize(name, value, error_class:)
        @name = name
        @value = value
        @error_class = error_class
      end

      def normalize
        value.to_s.strip.then do |normalized_value|
          raise error_class, "#{name} must be present" if normalized_value.empty?

          normalized_value.freeze
        end
      end

      private

      attr_reader :error_class, :name, :value
    end

    # Normalizes optional string-like values.
    class OptionalString
      def initialize(name, value, error_class:)
        @name = name
        @value = value
        @error_class = error_class
      end

      def normalize
        return nil unless [value].compact.any?

        PresentString.new(name, value, error_class:).normalize
      end

      private

      attr_reader :error_class, :name, :value
    end

    # Normalizes timestamps into immutable Time values.
    class Timestamp
      def initialize(name, value, error_class:)
        @name = name
        @value = value
        @error_class = error_class
      end

      def normalize
        return value.dup.freeze if value.is_a?(Time)

        raise error_class, "#{name} must be a Time"
      end

      private

      attr_reader :error_class, :name, :value
    end

    # Normalizes JSON-compatible hashes with stringified keys.
    class JsonHash
      def initialize(hash, error_class:, hash_message:, value_message:)
        @hash = hash
        @error_class = error_class
        @hash_message = hash_message
        @value_message = value_message
      end

      def normalize
        raise error_class, hash_message unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(key, value), normalized|
          normalized[normalize_key(key)] = normalize_value(value)
        end.freeze
      end

      private

      attr_reader :error_class, :hash, :hash_message, :value_message

      def normalize_key(key)
        PresentString.new('data key', key, error_class:).normalize
      end

      def normalize_value(value)
        case value
        when NilClass, TrueClass, FalseClass, Numeric
          value
        when String
          value.dup.freeze
        when Symbol
          value.to_s.freeze
        when Array
          normalized_entries = value.map { |entry| normalize_value(entry) }
          normalized_entries.freeze
        when Hash
          self.class.new(value, error_class:, hash_message:, value_message:).normalize
        else
          raise error_class, value_message
        end
      end
    end
  end
end
