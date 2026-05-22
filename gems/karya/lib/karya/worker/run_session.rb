# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Worker
    # Encapsulates the worker polling loop and associated runtime-state updates.
    class RunSession
      def initialize(worker:, iteration_limit:, normalized_poll_interval:, shutdown_controller:, stop_when_idle:)
        @worker = worker
        @iteration_limit = iteration_limit
        @normalized_poll_interval = normalized_poll_interval
        @shutdown_controller = shutdown_controller
        @stop_when_idle = stop_when_idle
        @iterations = 0
      end

      def call
        loop do
          return stop_loop if shutdown_controller.force_stop?

          result = run_iteration
          loop_result = resolve_loop_result(result)
          report_loop_state(loop_result, result)
          return loop_result unless loop_result.equal?(CONTINUE_RUNNING)

          sleep_if_needed(result)
        end
      end

      private

      attr_reader :iteration_limit, :iterations, :normalized_poll_interval, :shutdown_controller, :stop_when_idle, :worker

      def run_iteration
        worker.send(:report_runtime_state, 'polling')
        worker.send(:instrument, 'worker.poll', queues: worker.queues, stop_when_idle:, max_iterations: iteration_limit.normalize)
        @iterations += 1
        worker.send(:work_once_result, shutdown_controller)
      end

      def resolve_loop_result(result)
        RunLoopDecision.new(
          result:,
          state: {
            idle: result.equal?(NO_WORK_AVAILABLE),
            iterations:,
            iteration_limit:,
            lease_lost: result.equal?(LEASE_LOST),
            shutdown_controller:,
            stop_when_idle:
          }
        ).resolve
      end

      def report_loop_state(loop_result, result)
        return worker.send(:report_runtime_state, 'stopping') unless loop_result.equal?(CONTINUE_RUNNING)
        return unless result.equal?(NO_WORK_AVAILABLE) || result.equal?(LEASE_LOST)

        worker.send(:report_runtime_state, 'idle')
      end

      def sleep_if_needed(result)
        return unless (result.equal?(NO_WORK_AVAILABLE) || result.equal?(LEASE_LOST)) && normalized_poll_interval.positive?

        worker.send(:runtime).sleep(normalized_poll_interval)
      end

      def stop_loop
        worker.send(:report_runtime_state, 'stopping')
        nil
      end
    end
  end
end
