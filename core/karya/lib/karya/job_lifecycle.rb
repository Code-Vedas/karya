# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'base'

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
    EMPTY_TRANSITIONS = [].freeze

    @mutex = Mutex.new
    @extension_states = []
    @extension_terminal_states = []
    @extension_transitions = Hash.new { |hash, key| hash[key] = [] }
    @states_locked = nil
    @terminal_states_locked = nil
    @transitions_locked = nil

    def normalize_state(state)
      @mutex.synchronize do
        normalize_state_locked(state)
      end
    end

    def validate_state!(state)
      @mutex.synchronize do
        validate_state_locked!(normalize_state_name(state))
      end
    end

    def valid_transition?(from:, to:)
      @mutex.synchronize do
        normalized_from = normalize_state_locked(from)
        normalized_to = normalize_state_locked(to)

        transitions_locked.fetch(normalized_from, []).include?(normalized_to)
      end
    end

    def validate_transition!(from:, to:)
      @mutex.synchronize do
        normalized_from = normalize_state_locked(from)
        normalized_to = normalize_state_locked(to)
        return normalized_to if transitions_locked.fetch(normalized_from, []).include?(normalized_to)

        raise InvalidJobTransitionError,
              "Cannot transition job state from #{normalized_from.inspect} to #{normalized_to.inspect}"
      end
    end

    def terminal?(state)
      @mutex.synchronize do
        terminal_states_locked.include?(normalize_state_locked(state))
      end
    end

    def register_state(state, terminal: false)
      normalized_state = normalize_state_name(state).to_sym

      @mutex.synchronize do
        if (STATES + @extension_states).include?(normalized_state)
          raise InvalidJobStateError, "state must be new; #{normalized_state.inspect} is already registered"
        end

        @extension_states << normalized_state
        @extension_terminal_states << normalized_state if terminal
        invalidate_caches!
      end

      normalized_state
    end

    def register_transition(from:, to:)
      @mutex.synchronize do
        normalized_from = normalize_state_locked(from)
        normalized_to = normalize_state_locked(to)
        @extension_transitions[normalized_from] |= [normalized_to]
        invalidate_caches!

        normalized_to
      end
    end

    def states
      @mutex.synchronize do
        states_locked
      end
    end

    def transitions
      @mutex.synchronize do
        transitions_locked
      end
    end

    def terminal_states
      @mutex.synchronize do
        terminal_states_locked
      end
    end

    def clear_extensions!
      @mutex.synchronize do
        @extension_states.clear
        @extension_terminal_states.clear
        @extension_transitions.clear
        invalidate_caches!
      end
    end

    private

    def normalize_state_locked(state)
      validate_state_locked!(normalize_state_name(state))
    end
    module_function :normalize_state_locked
    private_class_method :normalize_state_locked

    def states_locked
      @states_locked ||= (STATES + @extension_states).freeze
    end
    module_function :states_locked
    private_class_method :states_locked

    def transitions_locked
      @transitions_locked ||= begin
        base_transitions = TRANSITIONS.transform_values { |next_states| next_states.dup.freeze }
        @extension_transitions.each do |state, next_states|
          base_transitions[state] = (base_transitions.fetch(state, []) + next_states).uniq.freeze
        end
        states_locked.each do |state|
          base_transitions[state] ||= EMPTY_TRANSITIONS
        end
        base_transitions.freeze
      end
    end
    module_function :transitions_locked
    private_class_method :transitions_locked

    def terminal_states_locked
      @terminal_states_locked ||= (TERMINAL_STATES + @extension_terminal_states).freeze
    end
    module_function :terminal_states_locked
    private_class_method :terminal_states_locked

    def invalidate_caches!
      @states_locked = nil
      @terminal_states_locked = nil
      @transitions_locked = nil
    end
    module_function :invalidate_caches!
    private_class_method :invalidate_caches!

    def normalize_state_name(state)
      normalized_value = state.to_s.strip.downcase.tr('-', '_')
      raise InvalidJobStateError, 'state must be present' if normalized_value.empty?

      normalized_value
    end
    module_function :normalize_state_name
    private_class_method :normalize_state_name

    def validate_state_locked!(state_name)
      matched_state = states_locked.find { |known_state| known_state.to_s == state_name }
      return matched_state if matched_state

      raise InvalidJobStateError, "Unknown job state: #{state_name.inspect}"
    end
    module_function :validate_state_locked!
    private_class_method :validate_state_locked!
  end
end
