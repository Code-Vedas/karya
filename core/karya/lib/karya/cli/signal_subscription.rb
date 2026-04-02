# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class CLI < Thor
    # Encapsulates process signal trap registration for CLI-owned runtimes.
    module SignalSubscription
      module_function

      def subscribe(signal, handler)
        previous_handler = Signal.trap(signal) { handler.call }
        -> { Signal.trap(signal, previous_handler) }
      end
    end
  end
end
