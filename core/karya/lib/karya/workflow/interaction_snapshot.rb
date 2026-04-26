# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Immutable inspection view of one workflow interaction delivery.
    class InteractionSnapshot
      KINDS = %i[signal event].freeze

      attr_reader :kind, :name, :payload, :received_at

      def initialize(**attributes)
        attributes = Attributes.new(attributes)
        @kind = attributes.kind
        @name = attributes.name
        @payload = attributes.payload
        @received_at = attributes.received_at
        freeze
      end

      # Validates and exposes interaction snapshot attributes.
      class Attributes
        REQUIRED_ATTRIBUTES = %i[kind name payload received_at].freeze

        def initialize(attributes)
          @attributes = attributes
          validate_keys
        end

        def kind
          normalized_kind = Kind.new(fetch(:kind)).to_sym
          return normalized_kind if KINDS.include?(normalized_kind)

          raise InvalidExecutionError, 'kind must be :signal or :event'
        end

        def name
          Workflow.send(:normalize_identifier, :name, fetch(:name))
        end

        def payload
          Payload.new(fetch(:payload)).to_h
        end

        def received_at
          Timestamp.new(:received_at, fetch(:received_at)).to_time
        end

        private

        attr_reader :attributes

        def fetch(name)
          attributes.fetch(name) { raise ArgumentError, "missing keyword: :#{name}" }
        end

        def validate_keys
          unknown_keys = attributes.keys - REQUIRED_ATTRIBUTES
          return if unknown_keys.empty?

          raise ArgumentError, "unknown keyword: :#{unknown_keys.first}"
        end
      end

      # Normalizes one interaction kind.
      class Kind
        def initialize(value)
          @value = value
        end

        def to_sym
          raise InvalidExecutionError, 'kind must be :signal or :event' unless value.is_a?(String) || value.is_a?(Symbol)

          value.to_sym
        end

        private

        attr_reader :value
      end

      # Normalizes and deep-freezes a JSON-compatible interaction payload.
      class Payload
        def initialize(payload)
          @payload = payload
        end

        def to_h
          raise InvalidExecutionError, 'payload must be a Hash' unless payload.is_a?(Hash)

          normalize_hash(payload)
        end

        private

        attr_reader :payload

        def normalize_hash(hash)
          hash.each_with_object({}) do |(key, value), normalized|
            raise InvalidExecutionError, 'payload keys must be Strings' unless key.is_a?(String)

            normalized[key.dup.freeze] = normalize_value(value)
          end.freeze
        end

        def normalize_value(value)
          case value
          when NilClass, TrueClass, FalseClass, Numeric
            value
          when String
            value.dup.freeze
          when Array
            value.map { |entry| normalize_value(entry) }.freeze
          when Hash
            normalize_hash(value)
          else
            raise InvalidExecutionError, 'payload values must be JSON-compatible'
          end
        end
      end

      # Normalizes timestamps into immutable values.
      class Timestamp
        def initialize(name, value)
          @name = name
          @value = value
        end

        def to_time
          return value.dup.freeze if value.is_a?(Time)

          raise InvalidExecutionError, "#{name} must be a Time"
        end

        private

        attr_reader :name, :value
      end

      private_constant :Attributes, :Kind, :KINDS, :Payload, :Timestamp
    end
  end
end
