# frozen_string_literal: true

require 'json'
require 'time'

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module OutboundEvents
    # Immutable CloudEvents-compatible outbound event envelope.
    class Event
      SPEC_VERSION = '1.0'
      DATA_CONTENT_TYPE = 'application/json'

      attr_reader :data, :id, :schema, :source, :subject, :time

      def initialize(**attributes)
        attributes = Attributes.new(attributes)
        @id = attributes.id
        @source = attributes.source
        @schema = attributes.schema
        @time = attributes.time
        @data = attributes.data
        @subject = attributes.subject
        freeze
      end

      def spec_version = SPEC_VERSION

      def type = schema.event_type

      def schema_version = schema.schema_version

      def data_schema = schema.data_schema

      def data_content_type = DATA_CONTENT_TYPE

      def to_h
        {
          'specversion' => spec_version,
          'id' => id,
          'source' => source,
          'type' => type,
          'time' => time.dup.getutc.iso8601,
          'subject' => subject,
          'datacontenttype' => data_content_type,
          'dataschema' => data_schema,
          'karyaschemaversion' => schema_version,
          'data' => data
        }.compact.freeze
      end

      def to_json(state = nil)
        JSON.generate(to_h, state)
      end

      # Validates and exposes outbound event construction attributes.
      class Attributes
        REQUIRED_ATTRIBUTES = %i[id source schema time data].freeze
        OPTIONAL_ATTRIBUTES = %i[subject].freeze
        SUPPORTED_ATTRIBUTES = (REQUIRED_ATTRIBUTES + OPTIONAL_ATTRIBUTES).freeze

        def initialize(attributes)
          @attributes = attributes
          validate_keys
        end

        def id
          PresentString.new(:id, fetch(:id), error_class: InvalidOutboundEventError).normalize
        end

        def source
          PresentString.new(:source, fetch(:source), error_class: InvalidOutboundEventError).normalize
        end

        def schema
          value = fetch(:schema)
          return value if value.is_a?(Schema)

          raise InvalidOutboundEventError, 'schema must be Karya::OutboundEvents::Schema'
        end

        def time
          Timestamp.new(:time, fetch(:time), error_class: InvalidOutboundEventError).normalize
        end

        def data
          JsonHash.new(
            fetch(:data),
            error_class: InvalidOutboundEventError,
            hash_message: 'data must be a Hash',
            value_message: 'data values must be JSON-compatible'
          ).normalize
        end

        def subject
          OptionalString.new(:subject, attributes.fetch(:subject, nil), error_class: InvalidOutboundEventError).normalize
        end

        private

        attr_reader :attributes

        def fetch(name)
          attributes.fetch(name) { raise ArgumentError, "missing keyword: :#{name}" }
        end

        def validate_keys
          unknown_keys = attributes.keys - SUPPORTED_ATTRIBUTES
          return if unknown_keys.empty?

          raise ArgumentError, "unknown keyword: :#{unknown_keys.first}"
        end
      end

      private_constant :Attributes
    end
  end
end
