# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'constants'
require_relative 'errors'
require_relative 'normalization'
require_relative 'extension_snapshots'
require_relative 'state_queries'

module Karya
  module JobLifecycle
    # Thread-safe state management and caching
    class StateManager
      include ExtensionSnapshots
      include StateQueries

      def initialize
        @mutex = Mutex.new
        @extension_state_names = []
        @extension_terminal_state_names = []
        @extension_transitions = Hash.new { |hash, key| hash[key] = [] }
        @state_names_locked = nil
        @terminal_state_names_locked = nil
        @transition_names_locked = nil
      end

      def normalize_state(state)
        synchronize do
          public_state(normalize_state_locked(state))
        end
      end

      def validate_state!(state)
        synchronize do
          public_state(validate_state_locked!(Normalization.normalize_state_name(state)))
        end
      end

      def valid_transition?(from:, to:)
        synchronize do
          normalized_from = normalize_state_locked(from)
          normalized_to = normalize_state_locked(to)

          transition_names_locked.fetch(normalized_from, Constants::EMPTY_TRANSITIONS).include?(normalized_to)
        end
      end

      def validate_transition!(from:, to:)
        synchronize do
          normalized_from = normalize_state_locked(from)
          normalized_to = normalize_state_locked(to)
          target_state = public_state(normalized_to)
          return target_state if transition_names_locked.fetch(normalized_from, Constants::EMPTY_TRANSITIONS).include?(normalized_to)

          raise InvalidJobTransitionError,
                "Cannot transition job state from #{public_state(normalized_from).inspect} to #{target_state.inspect}"
        end
      end

      def terminal?(state)
        synchronize do
          terminal_state_names_locked.include?(normalize_state_locked(state))
        end
      end

      def states
        synchronize do
          state_names_locked.map { |state_name| public_state(state_name) }.freeze
        end
      end

      def transitions
        synchronize do
          transition_names_locked.each_with_object({}) do |(state_name, next_state_names), transition_map|
            transition_map[public_state(state_name)] = transition_values(next_state_names)
          end.freeze
        end
      end

      def terminal_states
        synchronize do
          terminal_state_names_locked.map { |state_name| public_state(state_name) }.freeze
        end
      end

      def validate_state(state)
        synchronize do
          normalized_state_name = Normalization.normalize_state_name(state)
          validated_state_name = validate_state_locked(normalized_state_name)
          validated_state_name && public_state(validated_state_name)
        end
      end

      def validate_transition(from:, to:)
        validate_transition!(from: from, to: to)
      rescue InvalidJobStateError, InvalidJobTransitionError
        nil
      end

      private

      attr_reader :mutex

      def synchronize(&)
        @mutex.synchronize(&)
      end

      def normalize_state_locked(state)
        validate_state_locked!(Normalization.normalize_state_name(state))
      end

      def state_names_locked
        @state_names_locked ||= (Constants::CANONICAL_STATE_NAMES + @extension_state_names).freeze
      end

      def transition_names_locked
        @transition_names_locked ||= build_transition_names
      end

      def terminal_state_names_locked
        @terminal_state_names_locked ||= (Constants::CANONICAL_TERMINAL_STATE_NAMES + @extension_terminal_state_names).freeze
      end

      def invalidate_caches
        @state_names_locked = nil
        @terminal_state_names_locked = nil
        @transition_names_locked = nil
      end

      def validate_state_locked!(state_name)
        return state_name if state_names_locked.include?(state_name)

        raise InvalidJobStateError, "Unknown job state: #{state_name.inspect}"
      end

      def validate_state_locked(state_name)
        validate_state_locked!(state_name)
      rescue InvalidJobStateError
        nil
      end

      def add_extension_state_locked(state_name, terminal:)
        @extension_state_names << state_name
        @extension_terminal_state_names << state_name if terminal
        invalidate_caches
        state_name
      end

      def add_extension_transition_locked(from_state_name, to_state_name)
        @extension_transitions[from_state_name] |= [to_state_name]
        invalidate_caches
      end

      def clear_extensions_locked
        @extension_state_names.clear
        @extension_terminal_state_names.clear
        @extension_transitions.clear
        invalidate_caches
      end

      def extension_state_name_locked?(state_name)
        @extension_state_names.include?(state_name)
      end

      def canonical_state?(state_name)
        Constants::CANONICAL_STATE_NAMES.include?(state_name)
      end

      def build_transition_names
        base_transitions = initialize_base_transitions
        merge_extension_transitions(base_transitions)
        ensure_all_states_have_transitions(base_transitions)
        base_transitions.freeze
      end

      def initialize_base_transitions
        Constants::CANONICAL_TRANSITION_NAMES.transform_values do |next_state_names|
          next_state_names.dup.freeze
        end
      end

      def merge_extension_transitions(base_transitions)
        @extension_transitions.each do |state, next_states|
          base_transitions[state] = (base_transitions.fetch(state, []) + next_states).uniq.freeze
        end
      end

      def ensure_all_states_have_transitions(base_transitions)
        state_names_locked.each do |state_name|
          base_transitions[state_name] ||= Constants::EMPTY_TRANSITIONS
        end
      end
    end
  end
end
