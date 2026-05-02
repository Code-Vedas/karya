# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Backend
    # Immutable backend capability flags and documented parity exceptions.
    class Capabilities
      BOOLEAN_ATTRIBUTES = %i[
        job_persistence
        workflow_state
        schedule_state
        audit_history
        shared_processes
        multi_node
      ].freeze
      ATTRIBUTE_NAMES = (BOOLEAN_ATTRIBUTES + [:parity_exceptions]).freeze

      attr_reader(*BOOLEAN_ATTRIBUTES, :parity_exceptions)

      def initialize(**attributes)
        validate_attribute_names(attributes)

        @job_persistence = required_boolean(:job_persistence, attributes)
        @workflow_state = required_boolean(:workflow_state, attributes)
        @schedule_state = required_boolean(:schedule_state, attributes)
        @audit_history = required_boolean(:audit_history, attributes)
        @shared_processes = required_boolean(:shared_processes, attributes)
        @multi_node = required_boolean(:multi_node, attributes)
        @parity_exceptions = normalize_parity_exceptions(attributes.fetch(:parity_exceptions, []))
        freeze
      end

      BOOLEAN_ATTRIBUTES.each do |attribute_name|
        alias_method "#{attribute_name}?", attribute_name
      end

      private

      def required_boolean(name, attributes)
        normalize_boolean(name, attributes.fetch(name) { raise InvalidBackendSelectionError, "#{name} must be provided" })
      end

      def validate_attribute_names(attributes)
        unknown_attributes = attributes.keys - ATTRIBUTE_NAMES
        return if unknown_attributes.empty?

        raise_unknown_attribute_names_error(unknown_attributes)
      end

      def normalize_boolean(name, value)
        return value if [true, false].include?(value)

        raise InvalidBackendSelectionError, "#{name} must be boolean"
      end

      def normalize_parity_exceptions(values)
        raise InvalidBackendSelectionError, 'parity_exceptions must be an Array' unless values.is_a?(Array)

        values.map do |value|
          raise InvalidBackendSelectionError, 'parity_exceptions entries must be String values' unless value.is_a?(String)

          normalized_value = value.strip
          raise InvalidBackendSelectionError, 'parity_exceptions entries must be present' if normalized_value.empty?

          normalized_value.freeze
        end.freeze
      end

      def raise_unknown_attribute_names_error(unknown_attributes)
        raise InvalidBackendSelectionError, "unknown capability attributes: #{unknown_attributes.join(', ')}"
      end
    end
  end
end
