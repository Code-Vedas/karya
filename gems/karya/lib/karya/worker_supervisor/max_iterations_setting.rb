# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class WorkerSupervisor
    # Normalizes supervisor max-iteration settings while treating nil as unlimited.
    class MaxIterationsSetting
      def initialize(value)
        @value = value
      end

      def normalize
        return :unlimited if [nil, :unlimited].include?(value)

        Internal::RuntimeSupport::IterationLimit.new(
          value,
          error_class: InvalidWorkerSupervisorConfigurationError
        ).normalize
      end

      private

      attr_reader :value
    end
  end
end
