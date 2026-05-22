# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class WorkerSupervisor
    # Normalizes child pids returned by the configured forker.
    class Pid
      def initialize(value)
        @value = value
      end

      def normalize
        return @value if @value.is_a?(Integer) && @value.positive?

        raise InvalidWorkerSupervisorConfigurationError,
              "forker must return a positive Integer pid, got #{@value.inspect}"
      end
    end
  end
end
