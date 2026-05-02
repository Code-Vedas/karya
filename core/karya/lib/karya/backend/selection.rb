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
      SUPPORTED_IDENTIFIERS = %w[in_memory].freeze

      IDENTIFIER_ALIASES = {
        'InMemory' => 'in_memory',
        'inmemory' => 'in_memory',
        'in_memory' => 'in_memory'
      }.freeze

      CLASSIFICATIONS = {
        'in_memory' => :quick_setup_and_run,
        'sqlite' => :production_like_local,
        'redis' => :production_grade,
        'postgres' => :production_grade,
        'mysql' => :production_grade
      }.freeze

      attr_reader :identifier

      def self.normalize_identifier(value)
        normalized_input = normalize_identifier_input(value)
        normalized_alias = IDENTIFIER_ALIASES[normalized_input]
        return normalized_alias.freeze if normalized_alias

        raise UnsupportedBackendError,
              "unsupported backend #{normalized_input.inspect}; supported backends: #{SUPPORTED_IDENTIFIERS.join(', ')}"
      end

      def self.supported_identifier?(value)
        SUPPORTED_IDENTIFIERS.include?(normalize_identifier(value))
      rescue InvalidBackendSelectionError, UnsupportedBackendError
        false
      end

      def self.classification_for(value)
        CLASSIFICATIONS.fetch(normalize_identifier(value))
      end

      def self.quick_setup_and_run?(value)
        classification_for(value) == :quick_setup_and_run
      end

      def self.production_like_local?(value)
        classification_for(value) == :production_like_local
      end

      def self.production_grade?(value)
        classification_for(value) == :production_grade
      end

      def initialize(value)
        @identifier = self.class.normalize_identifier(value)
      end

      def classification
        self.class.classification_for(identifier)
      end

      def quick_setup_and_run?
        classification == :quick_setup_and_run
      end

      def production_like_local?
        classification == :production_like_local
      end

      def production_grade?
        classification == :production_grade
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
