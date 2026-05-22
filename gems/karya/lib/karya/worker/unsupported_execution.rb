# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Worker
    # Raises a configuration error when the registered handler is not executable.
    class UnsupportedExecution
      def initialize(handler_name)
        @handler_name = handler_name
      end

      def call(arguments:)
        _arguments = arguments
        raise InvalidWorkerConfigurationError, "handler #{@handler_name.inspect} must respond to #call or #perform"
      end
    end
  end
end
