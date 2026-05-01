# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Builds immutable snapshots for runtime hook payloads.
    class ImmutableHookPayload
      def self.snapshot(payload, error_class:)
        new(payload, error_class:).snapshot
      end

      def self.snapshot_pair(payload, error_class:)
        Array.new(2) { snapshot(payload, error_class:) }.freeze
      end

      def self.snapshot_key(value)
        return value if value.is_a?(Symbol)
        return value.frozen? ? value : value.dup.freeze if value.is_a?(String)

        raise ArgumentError, 'payload keys must be Symbols or Strings'
      end
      private_class_method :snapshot_key

      def initialize(payload, error_class:)
        @payload = payload
        @error_class = error_class
      end

      def snapshot
        snapshot_hash(payload)
      end

      private

      attr_reader :error_class, :payload

      def snapshot_hash(value)
        value.each_with_object({}) do |(key, item), duplicated|
          duplicated[self.class.send(:snapshot_key, key)] = snapshot_value(item)
        rescue ArgumentError => e
          raise error_class, e.message
        end.freeze
      end

      def snapshot_array(value)
        value.map { |item| snapshot_value(item) }.freeze
      end

      def snapshot_value(value)
        case value
        when Hash
          snapshot_hash(value)
        when Array
          snapshot_array(value)
        when String, Time
          value.frozen? ? value : value.dup.freeze
        when NilClass, TrueClass, FalseClass, Numeric, Symbol
          value
        else
          raise error_class, 'payload values must be nil, booleans, numerics, strings, symbols, times, arrays, or hashes'
        end
      end
    end
  end
end
