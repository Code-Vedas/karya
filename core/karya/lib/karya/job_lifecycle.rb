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
      RUNNING => [QUEUED, SUCCEEDED, FAILED, CANCELLED].freeze,
      SUCCEEDED => [].freeze,
      FAILED => [RETRY_PENDING].freeze,
      RETRY_PENDING => [QUEUED, CANCELLED].freeze,
      CANCELLED => [].freeze
    }.freeze

    TERMINAL_STATES = [SUCCEEDED, CANCELLED].freeze
    EMPTY_TRANSITIONS = [].freeze
    CANONICAL_STATE_NAMES = STATES.map(&:to_s).freeze
    CANONICAL_TERMINAL_STATE_NAMES = TERMINAL_STATES.map(&:to_s).freeze
    CANONICAL_TRANSITION_NAMES = TRANSITIONS.transform_keys(&:to_s).transform_values do |next_states|
      next_states.map(&:to_s).freeze
    end.freeze
    MAX_STATE_NAME_LENGTH = 64
    private_constant :EMPTY_TRANSITIONS, :CANONICAL_STATE_NAMES, :CANONICAL_TERMINAL_STATE_NAMES,
                     :CANONICAL_TRANSITION_NAMES, :MAX_STATE_NAME_LENGTH

    @mutex = Mutex.new
    @extension_state_names = []
    @extension_terminal_state_names = []
    @extension_transitions = Hash.new { |hash, key| hash[key] = [] }
    @state_names_locked = nil
    @terminal_state_names_locked = nil
    @transition_names_locked = nil

    def normalize_state(state)
      @mutex.synchronize do
        public_state(normalize_state_locked(state))
      end
    end

    def validate_state!(state)
      @mutex.synchronize do
        public_state(validate_state_locked!(normalize_state_name(state)))
      end
    end

    def valid_transition?(from:, to:)
      @mutex.synchronize do
        normalized_from = normalize_state_locked(from)
        normalized_to = normalize_state_locked(to)

        transition_names_locked.fetch(normalized_from, EMPTY_TRANSITIONS).include?(normalized_to)
      end
    end

    def validate_transition!(from:, to:)
      @mutex.synchronize do
        normalized_from = normalize_state_locked(from)
        normalized_to = normalize_state_locked(to)
        target_state = public_state(normalized_to)
        return target_state if transition_names_locked.fetch(normalized_from, EMPTY_TRANSITIONS).include?(normalized_to)

        raise InvalidJobTransitionError,
              "Cannot transition job state from #{public_state(normalized_from).inspect} to #{target_state.inspect}"
      end
    end

    def terminal?(state)
      @mutex.synchronize do
        terminal_state_names_locked.include?(normalize_state_locked(state))
      end
    end

    def register_state(state, terminal: false)
      normalized_state_name = normalize_state_name(state).freeze

      @mutex.synchronize do
        if state_names_locked.include?(normalized_state_name)
          raise InvalidJobStateError, "state must be new; #{normalized_state_name.inspect} is already registered"
        end

        @extension_state_names << normalized_state_name
        @extension_terminal_state_names << normalized_state_name if terminal
        invalidate_caches!
      end

      normalized_state_name
    end

    def register_transition(from:, to:)
      @mutex.synchronize do
        normalized_from = normalize_state_locked(from)
        normalized_to = normalize_state_locked(to)
        unless extension_state_name?(normalized_from) || extension_state_name?(normalized_to)
          raise InvalidJobTransitionError, 'extension transitions must involve at least one registered extension state'
        end
        raise InvalidJobTransitionError, 'terminal states cannot define outgoing transitions' if terminal_state_names_locked.include?(normalized_from)

        @extension_transitions[normalized_from] |= [normalized_to]
        invalidate_caches!

        public_state(normalized_to)
      end
    end

    def states
      @mutex.synchronize do
        state_names_locked.map { |state_name| public_state(state_name) }.freeze
      end
    end

    def transitions
      @mutex.synchronize do
        transition_names_locked.each_with_object({}) do |(state_name, next_state_names), transition_map|
          transition_map[public_state(state_name)] = transition_values(next_state_names)
        end.freeze
      end
    end

    def terminal_states
      @mutex.synchronize do
        terminal_state_names_locked.map { |state_name| public_state(state_name) }.freeze
      end
    end

    def clear_extensions!
      @mutex.synchronize do
        @extension_state_names.clear
        @extension_terminal_state_names.clear
        @extension_transitions.clear
        invalidate_caches!
      end
    end
    module_function :clear_extensions!
    private_class_method :clear_extensions!

    private

    def normalize_state_locked(state)
      validate_state_locked!(normalize_state_name(state))
    end
    module_function :normalize_state_locked
    private_class_method :normalize_state_locked

    def state_names_locked
      @state_names_locked ||= (CANONICAL_STATE_NAMES + @extension_state_names).freeze
    end
    module_function :state_names_locked
    private_class_method :state_names_locked

    def transition_names_locked
      @transition_names_locked ||= begin
        base_transitions = CANONICAL_TRANSITION_NAMES.transform_values { |next_state_names| next_state_names.dup.freeze }
        @extension_transitions.each do |state, next_states|
          base_transitions[state] = (base_transitions.fetch(state, []) + next_states).uniq.freeze
        end
        state_names_locked.each do |state_name|
          base_transitions[state_name] ||= EMPTY_TRANSITIONS
        end
        base_transitions.freeze
      end
    end
    module_function :transition_names_locked
    private_class_method :transition_names_locked

    def terminal_state_names_locked
      @terminal_state_names_locked ||= (CANONICAL_TERMINAL_STATE_NAMES + @extension_terminal_state_names).freeze
    end
    module_function :terminal_state_names_locked
    private_class_method :terminal_state_names_locked

    def invalidate_caches!
      @state_names_locked = nil
      @terminal_state_names_locked = nil
      @transition_names_locked = nil
    end
    module_function :invalidate_caches!
    private_class_method :invalidate_caches!

    def normalize_state_name(state)
      source = state.to_s.strip.downcase
      raise_blank_state_error! if source.empty?

      normalized_value = +''
      has_content = false
      previous_was_separator = false

      source.each_char do |character|
        if lowercase_letter?(character) || digit?(character)
          normalized_value << character
          has_content = true
          previous_was_separator = false
          next
        end

        next if !has_content || previous_was_separator

        normalized_value << '_'
        previous_was_separator = true
      end

      normalized_value.chomp!('_')
      raise_blank_state_error! unless has_content
      if normalized_value.length > MAX_STATE_NAME_LENGTH
        raise InvalidJobStateError,
              "Invalid job state name format: #{state.inspect} exceeds #{MAX_STATE_NAME_LENGTH} characters"
      end

      normalized_value
    end
    module_function :normalize_state_name
    private_class_method :normalize_state_name

    def validate_state_locked!(state_name)
      return state_name if state_names_locked.include?(state_name)

      raise InvalidJobStateError, "Unknown job state: #{state_name.inspect}"
    end
    module_function :validate_state_locked!
    private_class_method :validate_state_locked!

    def extension_state_name?(state_name)
      @extension_state_names.include?(state_name)
    end
    module_function :extension_state_name?
    private_class_method :extension_state_name?

    def public_state(state_name)
      return state_name.to_sym if CANONICAL_STATE_NAMES.include?(state_name)

      state_name
    end
    module_function :public_state
    private_class_method :public_state

    def transition_values(next_state_names)
      next_state_names.map { |next_state_name| public_state(next_state_name) }.freeze
    end
    module_function :transition_values
    private_class_method :transition_values

    def lowercase_letter?(character)
      character.between?('a', 'z')
    end
    module_function :lowercase_letter?
    private_class_method :lowercase_letter?

    def digit?(character)
      character.between?('0', '9')
    end
    module_function :digit?
    private_class_method :digit?

    def raise_blank_state_error!
      raise InvalidJobStateError, 'state must be present'
    end
    module_function :raise_blank_state_error!
    private_class_method :raise_blank_state_error!
  end
end
