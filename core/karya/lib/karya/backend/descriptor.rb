# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../primitives/identifier'

module Karya
  module Backend
    # Immutable backend identity and deployment posture description.
    class Descriptor
      CLASSIFICATIONS = %i[quick_setup_and_run production_like_local production_grade].freeze

      attr_reader :capabilities, :classification, :identifier

      def initialize(identifier:, classification:, capabilities:)
        @identifier = Selection.normalize_identifier(identifier)
        @classification = normalize_classification(classification)
        @capabilities = normalize_capabilities(capabilities)
        validate_classification_consistency
        freeze
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

      private

      def normalize_capabilities(value)
        return value if value.is_a?(Capabilities)

        raise InvalidBackendSelectionError, 'capabilities must be a Karya::Backend::Capabilities'
      end

      def normalize_classification(value)
        normalized_value = value.to_sym
        return normalized_value if CLASSIFICATIONS.include?(normalized_value)

        raise_invalid_classification_error
      rescue NoMethodError
        raise_invalid_classification_error
      end

      def raise_invalid_classification_error
        valid_classifications = CLASSIFICATIONS.map(&:inspect).join(', ')
        raise InvalidBackendSelectionError, "classification must be one of #{valid_classifications}"
      end

      def validate_classification_consistency
        expected_classification = Selection.classification_for(identifier)
        return if classification == expected_classification

        raise InvalidBackendSelectionError,
              "classification #{classification.inspect} does not match backend #{identifier.inspect}; expected #{expected_classification.inspect}"
      end
    end
  end
end
