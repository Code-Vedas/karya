# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'openssl'
require_relative 'values'
require_relative 'webhook_signature'

module Karya
  module OutboundEvents
    # Signs outbound webhook payloads with a stable HMAC-based scheme.
    class WebhookSigner
      DEFAULT_SCHEME = 'v1'
      DIGEST_ALGORITHM = 'SHA256'

      # Validates webhook secrets without altering their bytes.
      class Secret
        def initialize(value)
          @value = value
        end

        def normalize
          raise InvalidWebhookSignatureError, 'secret must be a String' unless value.is_a?(String)
          raise InvalidWebhookSignatureError, 'secret must be present' if value.empty?

          value.frozen? ? value : value.dup.freeze
        end

        private

        attr_reader :value
      end
      private_constant :Secret

      def initialize(secret:, scheme: DEFAULT_SCHEME)
        @secret = Secret.new(secret).normalize
        @scheme = PresentString.new(:scheme, scheme, error_class: InvalidWebhookSignatureError).normalize
      end

      def sign(body:, now:)
        raise InvalidWebhookSignatureError, 'body must be a String' unless body.is_a?(String)
        raise InvalidWebhookSignatureError, 'body must be present' if body.empty?

        normalized_now = Timestamp.new(:now, now, error_class: InvalidWebhookSignatureError).normalize
        timestamp = normalized_now.to_i.to_s
        signature_payload = String.new(capacity: timestamp.bytesize + body.bytesize + 1, encoding: Encoding::BINARY)
        signature_payload << timestamp.b << '.'.b << body.b
        digest = OpenSSL::HMAC.hexdigest(DIGEST_ALGORITHM, secret, signature_payload)
        WebhookSignature.new(
          scheme:,
          timestamp: normalized_now,
          digest:
        )
      end

      private

      attr_reader :scheme, :secret
    end
  end
end
