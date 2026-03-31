# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module JobLifecycle
    # Extension state and transition registration
    module Extension
      module_function

      def register_state(state, state_manager:, terminal: false)
        normalized_state_name = Normalization.normalize_state_name(state).freeze

        state_manager.synchronize do
          if state_manager.state_names_locked.include?(normalized_state_name)
            raise InvalidJobStateError, "state must be new; #{normalized_state_name.inspect} is already registered"
          end

          state_manager.extension_state_names << normalized_state_name
          state_manager.extension_terminal_state_names << normalized_state_name if terminal
          state_manager.invalidate_caches
        end

        normalized_state_name
      end

      def register_transition(from:, to:, state_manager:)
        state_manager.synchronize do
          normalized_from = state_manager.normalize_state_locked(from)
          normalized_to = state_manager.normalize_state_locked(to)
          unless state_manager.extension_state_name?(normalized_from) ||
                 state_manager.extension_state_name?(normalized_to)
            raise InvalidJobTransitionError,
                  'extension transitions must involve at least one registered extension state'
          end
          if state_manager.terminal_state_names_locked.include?(normalized_from)
            raise InvalidJobTransitionError, 'terminal states cannot define outgoing transitions'
          end

          state_manager.extension_transitions[normalized_from] |= [normalized_to]
          state_manager.invalidate_caches

          state_manager.public_state(normalized_to)
        end
      end

      def clear_extensions!(state_manager:)
        state_manager.synchronize do
          state_manager.extension_state_names.clear
          state_manager.extension_terminal_state_names.clear
          state_manager.extension_transitions.clear
          state_manager.invalidate_caches
        end
      end
    end
  end
end
