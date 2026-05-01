# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Builds immutable snapshots for runtime hook payloads.
    class ImmutableHookPayload
      def self.snapshot(payload)
        new(payload).snapshot
      end

      def self.snapshot_pair(payload)
        Array.new(2) { snapshot(payload) }.freeze
      end

      def self.snapshot_key(value)
        return value unless value.is_a?(String)

        value.frozen? ? value : value.dup.freeze
      end
      private_class_method :snapshot_key

      def initialize(payload)
        @payload = payload
      end

      def snapshot
        snapshot_hash(payload)
      end

      private

      attr_reader :payload

      def snapshot_hash(value)
        value.each_with_object({}) do |(key, item), duplicated|
          duplicated[self.class.send(:snapshot_key, key)] = snapshot_value(item)
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
        else
          value
        end
      end
    end
  end
end
