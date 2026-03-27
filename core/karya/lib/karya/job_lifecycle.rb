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

    @extension_states = []
    @extension_terminal_states = []
    @extension_transitions = Hash.new { |hash, key| hash[key] = [] }

    def normalize_state(state)
      normalized_state = normalize_state_value(state)
      validate_state!(normalized_state)
    end

    def validate_state!(state)
      return state if states.include?(state)

      raise InvalidJobStateError, "Unknown job state: #{state.inspect}"
    end

    def valid_transition?(from:, to:)
      transitions.fetch(normalize_state(from), []).include?(normalize_state(to))
    end

    def validate_transition!(from:, to:)
      normalized_from = normalize_state(from)
      normalized_to = normalize_state(to)
      return normalized_to if transitions.fetch(normalized_from, []).include?(normalized_to)

      raise InvalidJobTransitionError,
            "Cannot transition job state from #{normalized_from.inspect} to #{normalized_to.inspect}"
    end

    def terminal?(state)
      terminal_states.include?(normalize_state(state))
    end

    def register_state(state, terminal: false)
      normalized_state = normalize_state_value(state)
      raise InvalidJobStateError, 'state must be new' if states.include?(normalized_state)

      @extension_states << normalized_state
      @extension_terminal_states << normalized_state if terminal
      normalized_state
    end

    def register_transition(from:, to:)
      normalized_from = normalize_state(from)
      normalized_to = normalize_state(to)

      @extension_transitions[normalized_from] |= [normalized_to]
      normalized_to
    end

    def states
      (STATES + @extension_states).freeze
    end

    def transitions
      base_transitions = TRANSITIONS.transform_values(&:dup)
      @extension_transitions.each do |state, next_states|
        base_transitions[state] = (base_transitions.fetch(state, []) + next_states).uniq.freeze
      end
      base_transitions.freeze
    end

    def terminal_states
      (TERMINAL_STATES + @extension_terminal_states).freeze
    end

    def clear_extensions!
      @extension_states.clear
      @extension_terminal_states.clear
      @extension_transitions.clear
    end

    private

    def normalize_state_value(state)
      normalized_value = state.to_s.strip.downcase.tr('-', '_')
      raise InvalidJobStateError, 'state must be present' if normalized_value.empty?

      normalized_value.to_sym
    end
    module_function :normalize_state_value
  end
end
