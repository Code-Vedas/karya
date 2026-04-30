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

      def initialize(event:, signature: nil, body: nil)
        @event = normalize_event(event)
        @body = normalize_body(body)
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
        return nil if [nil].include?(value)
        return value if value.is_a?(WebhookSignature)

        raise InvalidOutboundEventError, 'signature must be Karya::OutboundEvents::WebhookSignature'
      end

      def normalize_body(value)
        Body.new(value, event: @event).normalize
      end

      def build_headers
        { 'Content-Type' => CONTENT_TYPE }.merge(signature&.headers || {})
      end

      # Normalizes one optional serialized body value for an outbound delivery.
      class Body
        def initialize(value, event:)
          @value = value
          @event = event
        end

        def normalize
          return event.to_json.freeze if [nil].include?(value)

          string_value = value if value.is_a?(String)
          return string_value if string_value&.frozen?
          return string_value.dup.freeze if string_value

          raise InvalidOutboundEventError, 'body must be a String'
        end

        private

        attr_reader :event, :value
      end

      private_constant :Body
    end
  end
end
