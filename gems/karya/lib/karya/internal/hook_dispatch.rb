# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Shares runtime hook payload normalization and dispatch flow.
    class HookDispatch
      def self.instrument(
        event:,
        payload:,
        payload_keywords:,
        payload_given:,
        instrumenter:,
        dispatch_outbound:,
        error_class:,
        mixed_payload_message:,
        emit_instrumentation:,
        emit_outbound_event:
      )
        return nil unless instrumenter || dispatch_outbound

        normalized_payload = PayloadInput.new(
          payload,
          payload_keywords,
          payload_given:,
          error_class:,
          mixed_payload_message:
        ).to_h

        if instrumenter && dispatch_outbound
          instrumentation_payload, outbound_payload = ImmutableHookPayload.snapshot_pair(
            normalized_payload,
            error_class:
          )
          emit_instrumentation.call(event, instrumentation_payload)
          emit_outbound_event.call(event, outbound_payload)
          return nil
        end

        snapshot = ImmutableHookPayload.snapshot(normalized_payload, error_class:)
        emit_instrumentation.call(event, snapshot) if instrumenter
        emit_outbound_event.call(event, snapshot) if dispatch_outbound
        nil
      end
    end
  end
end
