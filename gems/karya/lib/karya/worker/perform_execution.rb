# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Worker
    # Executes handlers that respond to `perform`.
    class PerformExecution
      def initialize(handler)
        @dispatcher = MethodDispatcher.new(parameters: handler.method(:perform).parameters)
        @handler = handler
      end

      def call(arguments:)
        @dispatcher.call(arguments:) do |mode, payload|
          dispatch(mode, payload)
        end
      end

      private

      def dispatch(mode, payload)
        case mode
        when :none
          @handler.perform
        when :positional_hash
          @handler.perform(payload)
        else
          @handler.perform(**payload)
        end
      end
    end
  end
end
