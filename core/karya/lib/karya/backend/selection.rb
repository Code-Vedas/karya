# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../primitives/identifier'

module Karya
  module Backend
    # Normalized backend selection without runtime boot wiring.
    class Selection
      KNOWN_IDENTIFIERS = %w[in_memory sqlite redis postgres mysql].freeze

      IDENTIFIER_ALIASES = {
        'InMemory' => 'in_memory',
        'inmemory' => 'in_memory',
        'in_memory' => 'in_memory',
        'sqlite' => 'sqlite',
        'redis' => 'redis',
        'postgres' => 'postgres',
        'postgresql' => 'postgres',
        'mysql' => 'mysql',
        'my_sql' => 'mysql'
      }.freeze

      attr_reader :identifier

      def self.normalize_identifier(value)
        normalized_input = normalize_identifier_input(value)
        normalized_alias = IDENTIFIER_ALIASES[normalized_input]
        return normalized_alias.freeze if normalized_alias

        raise UnsupportedBackendError,
              "unsupported backend #{normalized_input.inspect}; known backends: #{KNOWN_IDENTIFIERS.join(', ')}"
      end

      def self.known_identifier?(value)
        KNOWN_IDENTIFIERS.include?(normalize_identifier(value))
      rescue InvalidBackendSelectionError, UnsupportedBackendError
        false
      end

      def initialize(value)
        @identifier = self.class.normalize_identifier(value)
      end

      def self.normalize_identifier_input(value)
        if [NilClass, String, Symbol].any? { |klass| value.is_a?(klass) }
          return Primitives::Identifier.new(:backend, value, error_class: InvalidBackendSelectionError).normalize
        end

        raise InvalidBackendSelectionError, 'backend must be a String or Symbol'
      end
      private_class_method :normalize_identifier_input
    end
  end
end
