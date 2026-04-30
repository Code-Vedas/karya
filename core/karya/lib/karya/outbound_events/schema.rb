# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module OutboundEvents
    # Immutable versioned schema identity for one supported outbound event type.
    class Schema
      attr_reader :data_schema, :event_type, :schema_version

      def initialize(event_type:, schema_version:, data_schema:)
        @event_type = PresentString.new(:event_type, event_type, error_class: InvalidOutboundEventError).normalize
        @schema_version = PresentString.new(:schema_version, schema_version, error_class: InvalidOutboundEventError).normalize
        @data_schema = PresentString.new(:data_schema, data_schema, error_class: InvalidOutboundEventError).normalize
        freeze
      end
    end
  end
end
