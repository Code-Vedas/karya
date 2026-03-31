# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module JobLifecycle
    # Explicit registry object that owns lifecycle extension state and queries.
    class Registry
      attr_reader :state_manager

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
        validate_state!(state)
      rescue InvalidJobStateError
        nil
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
    end
  end
end
