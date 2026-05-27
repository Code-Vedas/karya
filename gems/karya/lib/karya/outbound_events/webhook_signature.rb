# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module OutboundEvents
    # Immutable webhook signature metadata for one outbound delivery.
    class WebhookSignature
      DEFAULT_SIGNATURE_HEADER = 'Karya-Webhook-Signature'
      DEFAULT_TIMESTAMP_HEADER = 'Karya-Webhook-Timestamp'

      attr_reader :digest, :scheme, :signature_header, :timestamp, :timestamp_header

      def initialize(
        scheme:,
        timestamp:,
        digest:,
        signature_header: DEFAULT_SIGNATURE_HEADER,
        timestamp_header: DEFAULT_TIMESTAMP_HEADER
      )
        @scheme = PresentString.new(:scheme, scheme, error_class: InvalidWebhookSignatureError).normalize
        @timestamp = Timestamp.new(:timestamp, timestamp, error_class: InvalidWebhookSignatureError).normalize
        @digest = PresentString.new(:digest, digest, error_class: InvalidWebhookSignatureError).normalize
        @signature_header = PresentString.new(:signature_header, signature_header, error_class: InvalidWebhookSignatureError).normalize
        @timestamp_header = PresentString.new(:timestamp_header, timestamp_header, error_class: InvalidWebhookSignatureError).normalize
        freeze
      end

      def header_value
        "#{scheme}=#{digest}"
      end

      def headers
        {
          timestamp_header => timestamp.to_i.to_s.freeze,
          signature_header => header_value.freeze
        }.freeze
      end
    end
  end
end
