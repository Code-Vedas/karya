# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module JobLifecycle
    # Explicit registry object that owns lifecycle extension state and queries.
    class Registry
      def initialize(state_manager: StateManager.new)
        @state_manager = state_manager
      end

      def normalize_state(state)
        state_manager.normalize_state(state)
      end

      def validate_state!(state)
        state_manager.validate_state!(state)
      end

      def validate_state(state)
        normalized_state_name = validate_state_locked(Normalization.normalize_state_name(state))
        normalized_state_name && public_state(normalized_state_name)
      end

      def valid_transition?(from:, to:)
        state_manager.valid_transition?(from:, to:)
      end

      def validate_transition!(from:, to:)
        state_manager.validate_transition!(from:, to:)
      end

      def validate_transition(from:, to:)
        validate_transition!(from:, to:)
      rescue InvalidJobStateError, InvalidJobTransitionError
        nil
      end

      def terminal?(state)
        state_manager.terminal?(state)
      end

      def register_state(state, terminal: false)
        Extension.register_state(state, terminal:, state_manager:)
      end

      def register_transition(from:, to:)
        Extension.register_transition(from:, to:, state_manager:)
      end

      def states
        state_manager.states
      end

      def transitions
        state_manager.transitions
      end

      def terminal_states
        state_manager.terminal_states
      end

      def clear_extensions!
        Extension.clear_extensions!(state_manager:)
      end

      def clear_extensions
        clear_extensions!
      end

      private

      attr_reader :state_manager

      def extension_state_names
        state_manager.extension_state_names
      end

      def extension_terminal_state_names
        state_manager.extension_terminal_state_names
      end

      def extension_transitions
        state_manager.extension_transitions
      end

      def mutex
        state_manager.mutex
      end

      def normalize_state_locked(state)
        state_manager.normalize_state_locked(state)
      end

      def state_names_locked
        state_manager.state_names_locked
      end

      def transition_names_locked
        state_manager.transition_names_locked
      end

      def terminal_state_names_locked
        state_manager.terminal_state_names_locked
      end

      def invalidate_caches
        state_manager.invalidate_caches
      end

      def validate_state_locked!(state_name)
        state_manager.validate_state_locked!(state_name)
      end

      def validate_state_locked(state_name)
        validate_state_locked!(state_name)
      rescue InvalidJobStateError
        nil
      end

      def extension_state_name?(state_name)
        state_manager.extension_state_name?(state_name)
      end

      def public_state(state_name)
        state_manager.public_state(state_name)
      end

      def transition_values(next_state_names)
        state_manager.transition_values(next_state_names)
      end
    end
  end
end
