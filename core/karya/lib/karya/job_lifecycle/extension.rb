# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'errors'
require_relative 'normalization'

module Karya
  module JobLifecycle
    # Extension state and transition registration
    module Extension
      module_function

      def register_state(state, state_manager:, terminal: false)
        normalized_state_name = Normalization.normalize_state_name(state).freeze

        state_manager.send(:synchronize) do
          if state_manager.send(:state_names_locked).include?(normalized_state_name)
            raise InvalidJobStateError, "state must be new; #{normalized_state_name.inspect} is already registered"
          end

          state_manager.send(:add_extension_state_locked, normalized_state_name, terminal:)
        end

        normalized_state_name
      end

      def register_transition(from:, to:, state_manager:)
        state_manager.send(:synchronize) do
          normalized_from = state_manager.send(:normalize_state_locked, from)
          normalized_to = state_manager.send(:normalize_state_locked, to)
          unless state_manager.send(:extension_state_name_locked?, normalized_from) ||
                 state_manager.send(:extension_state_name_locked?, normalized_to)
            raise InvalidJobTransitionError,
                  'extension transitions must involve at least one registered extension state'
          end
          if state_manager.send(:terminal_state_names_locked).include?(normalized_from)
            raise InvalidJobTransitionError, 'terminal states cannot define outgoing transitions'
          end

          state_manager.send(:add_extension_transition_locked, normalized_from, normalized_to)

          state_manager.send(:public_state, normalized_to)
        end
      end

      def clear_extensions!(state_manager:)
        state_manager.send(:synchronize) do
          state_manager.send(:clear_extensions_locked)
        end
      end
    end
  end
end
