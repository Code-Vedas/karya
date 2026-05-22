# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require_relative '../internal/payload_input'
require_relative '../primitives/callable'
require_relative 'delivery'
require_relative 'schema_catalog'
require_relative 'webhook_signer'

module Karya
  module OutboundEvents
    # Builds canonical outbound deliveries from runtime instrumentation events.
    class Dispatcher
      def initialize(delivery_handler:, signer: nil, clock: -> { Time.now.utc }, event_id_generator: -> { SecureRandom.uuid })
        @delivery_handler = Primitives::Callable.new(:delivery_handler, delivery_handler, error_class: InvalidOutboundEventError).normalize
        @signer = normalize_signer(signer)
        @clock = Primitives::Callable.new(:clock, clock, error_class: InvalidOutboundEventError).normalize
        @event_id_generator = Primitives::Callable.new(
          :event_id_generator,
          event_id_generator,
          error_class: InvalidOutboundEventError
        ).normalize
      end

      def call(event_name, payload = Internal::PayloadInput::ABSENT, **payload_keywords)
        return nil unless SchemaCatalog.supported?(event_name)

        occurred_at = clock.call
        raise InvalidOutboundEventError, 'clock must return a Time' unless occurred_at.is_a?(Time)

        payload_given = !payload.equal?(Internal::PayloadInput::ABSENT)

        event = SchemaCatalog.build_event(
          event_name:,
          payload: Internal::PayloadInput.new(
            payload_given ? payload : nil,
            payload_keywords,
            payload_given:,
            error_class: InvalidOutboundEventError,
            mixed_payload_message: 'payload must be a Hash when keyword payload is also given'
          ).to_h,
          occurred_at:,
          event_id: event_id_generator.call
        )
        body = event.to_json.freeze
        signature = signer&.sign(body:, now: occurred_at)
        delivery = Delivery.new(event:, signature:, body:)
        delivery_handler.call(delivery)
        delivery
      end

      private

      attr_reader :clock, :delivery_handler, :event_id_generator, :signer

      def normalize_signer(value)
        return nil if [nil].include?(value)
        return value if value.is_a?(WebhookSigner)

        raise InvalidOutboundEventError, 'signer must be Karya::OutboundEvents::WebhookSigner'
      end
    end
  end
end
