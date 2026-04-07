# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class WorkerSupervisor
    # Runs the supervisor child-management loop and owns run-local counters.
    class RunSession
      CONTINUE_RUNNING = Object.new

      def initialize(supervisor:, shutdown_controller:)
        @supervisor = supervisor
        @shutdown_controller = shutdown_controller
        @child_pids = {}
        @completed_processes = 0
        @failed_bounded_child = false
        @graceful_signal_sent = false
        @forced_signal_sent = false
      end

      attr_reader :child_pids

      def call
        loop do
          desired_children = supervisor.send(:desired_child_count, shutdown_controller, @completed_processes)
          supervisor.send(:spawn_missing_children, child_pids, desired_children, shutdown_controller)
          update_signal_state
          return finished_run_status if desired_children.zero? && child_pids.empty?

          wait_result = process_wait_result
          return wait_result unless wait_result.equal?(CONTINUE_RUNNING)
        end
      end

      def request_drain
        perform_shutdown_request(shutdown_controller.begin_drain, RuntimeStateStore::DRAINING_PHASE)
      end

      def request_force_stop
        perform_shutdown_request(shutdown_controller.force_stop!, RuntimeStateStore::FORCE_STOPPING_PHASE)
      end

      private

      attr_reader :shutdown_controller, :supervisor

      def perform_shutdown_request(advanced, phase)
        return unless advanced

        supervisor.send(:runtime_state_store).mark_supervisor_phase(phase)
      ensure
        WakeupSignal.interrupt(WAKEUP_SIGNAL) if advanced
      end

      def update_signal_state
        @graceful_signal_sent, @forced_signal_sent = supervisor.send(
          :signal_children_for_shutdown,
          child_pids:,
          shutdown_controller:,
          graceful_signal_sent: @graceful_signal_sent,
          forced_signal_sent: @forced_signal_sent
        )
      end

      def finished_run_status
        return 1 if shutdown_controller.force_stop? || @failed_bounded_child

        0
      end

      def process_wait_result
        waited_child = supervisor.send(:runtime).wait_for_child
        return handle_missing_waited_child unless waited_child

        handle_waited_child(waited_child)
      end

      def handle_missing_waited_child
        pruned_children = supervisor.send(:prune_stale_children, child_pids)
        @completed_processes, @failed_bounded_child = supervisor.send(
          :update_pruned_child_state,
          completed_children: @completed_processes,
          failed_bounded_child: @failed_bounded_child,
          pruned_children:,
          shutdown_controller:
        )
        CONTINUE_RUNNING
      end

      def handle_waited_child(waited_child)
        pid, status = waited_child
        return CONTINUE_RUNNING unless child_pids.delete(pid)

        supervisor.send(:runtime_state_store).mark_child_stopped(pid)
        supervisor.send(:instrument, 'supervisor.child.exited', pid:, success: status.success?)
        @completed_processes, @failed_bounded_child = supervisor.send(
          :update_bounded_child_state,
          completed_children: @completed_processes,
          failed_bounded_child: @failed_bounded_child,
          shutdown_controller:,
          status:
        )
        CONTINUE_RUNNING
      end
    end
  end
end
