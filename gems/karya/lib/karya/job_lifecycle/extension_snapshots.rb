# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module JobLifecycle
    # Read-only snapshot accessors for extension state internals.
    module ExtensionSnapshots
      def extension_state_names
        synchronize do
          @extension_state_names.dup.freeze
        end
      end

      def extension_terminal_state_names
        synchronize do
          @extension_terminal_state_names.dup.freeze
        end
      end

      def extension_transitions
        synchronize do
          @extension_transitions.each_with_object({}) do |(state_name, next_states), copy|
            copy[state_name] = next_states.dup.freeze
          end.freeze
        end
      end
    end
  end
end
