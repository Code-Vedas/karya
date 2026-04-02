# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Worker
    # Decides whether the run loop should continue, return a result, or stop.
    class RunLoopDecision
      def initialize(result:, state:)
        @result = result
        @state = state
      end

      def resolve
        return nil if shutdown_controller.stop_after_iteration?
        return nil if stop_when_idle && idle
        return CONTINUE_RUNNING unless iteration_limit.reached?(iterations)
        return nil if idle || lease_lost

        @result
      end

      private

      def idle
        @state.fetch(:idle)
      end

      def iteration_limit
        @state.fetch(:iteration_limit)
      end

      def iterations
        @state.fetch(:iterations)
      end

      def lease_lost
        @state.fetch(:lease_lost)
      end

      def shutdown_controller
        @state.fetch(:shutdown_controller)
      end

      def stop_when_idle
        @state.fetch(:stop_when_idle)
      end
    end
  end
end
