# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'outbound_events/delivery'
require_relative 'outbound_events/dispatcher'
require_relative 'outbound_events/event'
require_relative 'outbound_events/schema'
require_relative 'outbound_events/schema_catalog'
require_relative 'outbound_events/values'
require_relative 'outbound_events/webhook_signature'
require_relative 'outbound_events/webhook_signer'
require_relative 'outbound_events/webhook_verifier'

module Karya
  # Raised when outbound event input cannot be normalized into a supported contract.
  class InvalidOutboundEventError < Error; end

  # Raised when a caller asks for an outbound event that is not part of the supported contract.
  class UnsupportedOutboundEventError < Error; end

  # Raised when a webhook signature cannot be parsed or verified.
  class InvalidWebhookSignatureError < Error; end

  # Shared outbound event contracts for external delivery and verification.
  module OutboundEvents
  end
end
