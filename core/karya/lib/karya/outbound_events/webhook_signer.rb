# frozen_string_literal: true

require 'openssl'

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module OutboundEvents
    # Signs outbound webhook payloads with a stable HMAC-based scheme.
    class WebhookSigner
      DEFAULT_SCHEME = 'v1'
      DIGEST_ALGORITHM = 'SHA256'

      def initialize(secret:, scheme: DEFAULT_SCHEME)
        @secret = PresentString.new(:secret, secret, error_class: InvalidWebhookSignatureError).normalize
        @scheme = PresentString.new(:scheme, scheme, error_class: InvalidWebhookSignatureError).normalize
      end

      def sign(body:, now:)
        normalized_body = PresentString.new(:body, body, error_class: InvalidWebhookSignatureError).normalize
        normalized_now = Timestamp.new(:now, now, error_class: InvalidWebhookSignatureError).normalize
        timestamp = normalized_now.to_i.to_s
        digest = OpenSSL::HMAC.hexdigest(DIGEST_ALGORITHM, secret, "#{timestamp}.#{normalized_body}")
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
