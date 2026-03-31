# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Worker
    # Builds executable handler entries from registered runtime handlers.
    class HandlerExecution
      def self.build(handler:, handler_name:)
        return CallableExecution.new(handler) if callable?(handler)
        return PerformExecution.new(handler) if performable?(handler)

        UnsupportedExecution.new(handler_name)
      end

      def self.callable?(handler)
        handler.public_method(:call)
        true
      rescue NameError
        false
      end

      def self.performable?(handler)
        handler.public_method(:perform)
        true
      rescue NameError
        false
      end
    end
  end
end
