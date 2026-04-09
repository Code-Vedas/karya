# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class CLI < Thor
    # Parses one CLI handler mapping in `NAME=CONSTANT` format.
    class MappingEntry
      def initialize(entry)
        @entry = entry
      end

      def name
        split_entry.fetch(0)
      end

      def constant_name
        split_entry.fetch(1)
      end

      def merge_into(handlers, duplicate_error_class: ArgumentError)
        raise duplicate_error_class, "duplicate handler mapping for #{name.inspect}" if handlers.key?(name)

        handlers[name] = Karya::ConstantResolver.new(constant_name).resolve
      rescue Karya::ConstantResolutionError => e
        raise Thor::Error, e.message
      end

      private

      attr_reader :entry

      def split_entry
        @split_entry ||= begin
          name, constant_name = entry.to_s.split('=', 2)
          raise Thor::Error, "handler entries must use NAME=CONSTANT format: #{entry.inspect}" if name.to_s.strip.empty? || constant_name.to_s.strip.empty?

          [name.strip, constant_name.strip].freeze
        end
      end
    end
  end
end
