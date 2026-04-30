# frozen_string_literal: true

require 'openssl'

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module OutboundEvents
    # Verifies signed outbound webhook payloads for external consumers.
    class WebhookVerifier
      DEFAULT_MAX_SKEW_SECONDS = 300

      def initialize(secret:, max_skew_seconds: DEFAULT_MAX_SKEW_SECONDS)
        @max_skew_seconds = normalize_max_skew_seconds(max_skew_seconds)
        @signer = WebhookSigner.new(secret:)
      end

      def verify(body:, headers:, now:)
        validate(body:, headers:, now:)
      end

      def validate(body:, headers:, now:)
        enforce_signature_validity(body:, headers:, now:)
      end

      def enforce_signature_validity(body:, headers:, now:)
        enforce_signature_validity!(body:, headers:, now:)
        true
      rescue InvalidWebhookSignatureError
        false
      end

      def enforce_signature_validity!(body:, headers:, now:)
        signature_header = HeaderValue.new(headers, WebhookSignature::DEFAULT_SIGNATURE_HEADER).fetch
        timestamp_header = HeaderValue.new(headers, WebhookSignature::DEFAULT_TIMESTAMP_HEADER).fetch
        scheme, digest = SignatureHeader.new(signature_header).parse
        timestamp = parse_timestamp(timestamp_header)
        validate_timestamp(timestamp, now)
        expected_signature = signer.sign(body:, now: timestamp)
        expected_digest = expected_signature.digest

        raise InvalidWebhookSignatureError, "unsupported signature scheme #{scheme.inspect}" unless scheme == expected_signature.scheme

        digest_matches = digest.bytesize == expected_digest.bytesize &&
                         OpenSSL.fixed_length_secure_compare(digest, expected_digest)
        raise InvalidWebhookSignatureError, 'signature digest does not match' unless digest_matches
      end

      private

      attr_reader :max_skew_seconds, :signer

      def normalize_max_skew_seconds(value)
        raise InvalidWebhookSignatureError, 'max_skew_seconds must be an Integer' unless value.is_a?(Integer)
        raise InvalidWebhookSignatureError, 'max_skew_seconds must be greater than or equal to 0' if value.negative?

        value
      end

      def parse_timestamp(value)
        timestamp = Integer(value, 10)
        Time.at(timestamp).utc
      rescue ArgumentError
        raise InvalidWebhookSignatureError, 'timestamp header must be an integer epoch second'
      end

      def validate_timestamp(timestamp, now)
        normalized_now = Timestamp.new(:now, now, error_class: InvalidWebhookSignatureError).normalize
        skew = (normalized_now.to_i - timestamp.to_i).abs
        return if skew <= max_skew_seconds

        raise InvalidWebhookSignatureError, 'timestamp is outside the allowed verification window'
      end

      # Fetches and normalizes one webhook verification header.
      class HeaderValue
        def initialize(headers, key)
          @headers = headers
          @key = key
        end

        def fetch
          raise InvalidWebhookSignatureError, 'headers must be a Hash' unless headers.is_a?(Hash)

          normalized_value = OptionalString.new(
            key,
            [headers[key], headers[key.downcase]].compact.first,
            error_class: InvalidWebhookSignatureError
          ).normalize
          normalized_value || raise(InvalidWebhookSignatureError, "#{key} header must be present")
        end

        private

        attr_reader :headers, :key
      end

      # Parses the versioned webhook signature header.
      class SignatureHeader
        def initialize(value)
          @value = value
        end

        def parse
          /\A([A-Za-z0-9_]+)=([0-9a-f]+)\z/.match(value).then do |match|
            raise InvalidWebhookSignatureError, 'signature header must use <scheme>=<digest> format' unless match

            [match[1], match[2]]
          end
        end

        private

        attr_reader :value
      end
    end
  end
end
