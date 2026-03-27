# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  # Raised when a job state is not part of the canonical lifecycle.
  class InvalidJobStateError < Error; end

  # Raised when a lifecycle transition is not allowed.
  class InvalidJobTransitionError < Error; end

  # Canonical lifecycle rules for queued job instances.
  module JobLifecycle
    module_function

    SUBMISSION = :submission
    QUEUED = :queued
    RESERVED = :reserved
    RUNNING = :running
    SUCCEEDED = :succeeded
    FAILED = :failed
    RETRY_PENDING = :retry_pending
    CANCELLED = :cancelled

    STATES = [
      SUBMISSION,
      QUEUED,
      RESERVED,
      RUNNING,
      SUCCEEDED,
      FAILED,
      RETRY_PENDING,
      CANCELLED
    ].freeze

    TRANSITIONS = {
      SUBMISSION => [QUEUED].freeze,
      QUEUED => [RESERVED, CANCELLED].freeze,
      RESERVED => [RUNNING, QUEUED, CANCELLED].freeze,
      RUNNING => [SUCCEEDED, FAILED, CANCELLED].freeze,
      SUCCEEDED => [].freeze,
      FAILED => [RETRY_PENDING].freeze,
      RETRY_PENDING => [QUEUED, CANCELLED].freeze,
      CANCELLED => [].freeze
    }.freeze

    TERMINAL_STATES = [SUCCEEDED, CANCELLED].freeze

    def normalize_state(state)
      normalized_state = state.to_s.strip.downcase.tr('-', '_').to_sym
      validate_state!(normalized_state)
    end

    def validate_state!(state)
      return state if STATES.include?(state)

      raise InvalidJobStateError, "Unknown job state: #{state.inspect}"
    end

    def valid_transition?(from:, to:)
      TRANSITIONS.fetch(normalize_state(from)).include?(normalize_state(to))
    end

    def validate_transition!(from:, to:)
      normalized_from = normalize_state(from)
      normalized_to = normalize_state(to)
      return normalized_to if TRANSITIONS.fetch(normalized_from).include?(normalized_to)

      raise InvalidJobTransitionError,
            "Cannot transition job state from #{normalized_from.inspect} to #{normalized_to.inspect}"
    end

    def terminal?(state)
      TERMINAL_STATES.include?(normalize_state(state))
    end
  end
end
