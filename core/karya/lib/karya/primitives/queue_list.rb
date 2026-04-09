# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Primitives
    # Normalizes queue lists into a frozen list of queue identifiers.
    class QueueList
      def initialize(values, error_class:)
        @values = values
        @error_class = error_class
      end

      def normalize
        normalized_values = Array(values).map do |value|
          Identifier.new(:queue, value, error_class:).normalize
        end
        raise error_class, 'queues must be present' if normalized_values.empty?

        duplicate_values = normalized_values
                           .group_by(&:itself)
                           .select { |_queue, entries| entries.length > 1 }
                           .keys
        raise error_class, "queues must be unique: #{duplicate_values.join(', ')}" unless duplicate_values.empty?

        normalized_values.freeze
      end

      private

      attr_reader :values, :error_class
    end
  end
end
