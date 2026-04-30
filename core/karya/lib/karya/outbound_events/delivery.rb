# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module OutboundEvents
    # Immutable serialized outbound delivery with canonical headers and body.
    class Delivery
      CONTENT_TYPE = 'application/cloudevents+json'

      attr_reader :body, :event, :headers, :signature

      def initialize(event:, signature: nil)
        @event = normalize_event(event)
        @body = @event.to_json.freeze
        @signature = normalize_signature(signature)
        @headers = build_headers.freeze
        freeze
      end

      private

      def normalize_event(value)
        return value if value.is_a?(Event)

        raise InvalidOutboundEventError, 'event must be Karya::OutboundEvents::Event'
      end

      def normalize_signature(value)
        return nil unless [value].compact.any?
        return value if value.is_a?(WebhookSignature)

        raise InvalidOutboundEventError, 'signature must be Karya::OutboundEvents::WebhookSignature'
      end

      def build_headers
        { 'Content-Type' => CONTENT_TYPE }.merge(signature&.headers || {})
      end
    end
  end
end
