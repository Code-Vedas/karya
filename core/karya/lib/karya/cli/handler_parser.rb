# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class CLI < Thor
    # Parses explicit handler mapping entries passed through the CLI.
    class HandlerParser
      def self.parse(entries)
        new(entries).parse
      end

      def initialize(entries)
        @entries = entries
      end

      def parse
        entries.each_with_object({}) do |entry, handlers|
          MappingEntry.new(entry).merge_into(handlers, duplicate_error_class: Thor::Error)
        end
      end

      private

      attr_reader :entries
    end
  end
end
