# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Normalizes positional and keyword payload inputs into one Hash.
    class PayloadInput
      # Unique sentinel for omitted positional payload arguments.
      class Absent
        def self.instance
          @instance ||= new.freeze
        end

        private_class_method :new
      end
      private_constant :Absent

      ABSENT = Absent.instance

      def initialize(payload, payload_keywords, payload_given:, error_class:, mixed_payload_message:)
        @payload = payload
        @payload_keywords = payload_keywords
        @payload_given = payload_given
        @error_class = error_class
        @mixed_payload_message = mixed_payload_message
      end

      def to_h
        return payload_keywords unless payload_given

        payload_is_hash = payload.is_a?(Hash)

        if payload_keywords.empty?
          raise error_class, 'payload must be a Hash' unless payload_is_hash

          return payload
        end

        raise error_class, mixed_payload_message unless payload_is_hash

        payload.merge(payload_keywords)
      end

      private

      attr_reader :error_class, :mixed_payload_message, :payload, :payload_given, :payload_keywords
    end
  end
end
