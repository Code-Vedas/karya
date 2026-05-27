# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Worker
    # Executes handlers that respond to `call`.
    class CallableExecution
      def initialize(handler)
        parameter_source = case handler
                           when Proc, Method, UnboundMethod
                             handler
                           else
                             handler.method(:call)
                           end
        @dispatcher = MethodDispatcher.new(parameters: parameter_source.parameters)
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
          @handler.call
        when :positional_hash
          @handler.call(payload)
        else
          @handler.call(**payload)
        end
      end
    end
  end
end
