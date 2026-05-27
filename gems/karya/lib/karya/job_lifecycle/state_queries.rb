# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module JobLifecycle
    # Internal state query and value helpers for StateManager.
    module StateQueries
      private

      def extension_state_name?(state_name)
        synchronize do
          extension_state_name_locked?(state_name)
        end
      end

      def public_state(state_name)
        canonical_state?(state_name) ? state_name.to_sym : state_name
      end

      def transition_values(next_state_names)
        next_state_names.map { |next_state_name| public_state(next_state_name) }.freeze
      end
    end
  end
end
