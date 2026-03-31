# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'internal/runtime_support/signal_restorer'
require_relative 'internal/runtime_support/iteration_limit'
require_relative 'primitives/identifier'
require_relative 'primitives/queue_list'
require_relative 'primitives/positive_finite_number'
require_relative 'primitives/non_negative_finite_number'
require_relative 'primitives/callable'
require_relative 'primitives/optional_callable'
require_relative 'primitives/positive_integer'
require_relative 'worker_supervisor/child_process_runner'
require_relative 'worker_supervisor/configuration'
require_relative 'worker_supervisor/handler_mapping'
require_relative 'worker_supervisor/max_iterations_setting'
require_relative 'worker_supervisor/pid'
require_relative 'worker_supervisor/runtime'
require_relative 'worker_supervisor/shutdown_controller'

module Karya
  # Raised when worker supervisor bootstrap input is invalid.
  class InvalidWorkerSupervisorConfigurationError < Error; end

  # Supervisor process that manages forked worker children.
  class WorkerSupervisor
    DEFAULT_PROCESSES = 1
    DEFAULT_THREADS = 1
    FORCEFUL_SIGNAL = 'KILL'
    GRACEFUL_SIGNAL = 'TERM'
    NOOP_SUBSCRIPTION = -> {}.freeze
    SIGNALS = %w[INT TERM].freeze

    def initialize(queue_store:, configuration: nil, runtime: nil, child_worker_class: Worker, **options)
      extracted_options = options.dup
      @queue_store = queue_store
      @configuration = configuration || Configuration.from_options(extracted_options)
      @runtime = runtime || Runtime.from_options(extracted_options)
      @child_worker_class = child_worker_class
      raise_unknown_option_error(extracted_options) unless extracted_options.empty?
    end

    def run
      shutdown_controller = ShutdownController.new
      child_pids = {}
      completed_processes = 0
      failed_bounded_child = false
      graceful_signal_sent = false
      forced_signal_sent = false

      with_signal_handlers(shutdown_controller) do
        loop do
          desired_children = desired_child_count(shutdown_controller, completed_processes)
          spawn_missing_children(child_pids, desired_children, shutdown_controller)
          graceful_signal_sent, forced_signal_sent = signal_children_for_shutdown(
            child_pids:,
            shutdown_controller:,
            graceful_signal_sent:,
            forced_signal_sent:
          )

          if desired_children.zero? && child_pids.empty?
            return 1 if shutdown_controller.force_stop? || failed_bounded_child

            return 0
          end

          waited_child = runtime.wait_for_child
          next unless waited_child

          pid, status = waited_child
          next unless child_pids.delete(pid)

          instrument('supervisor.child.exited', pid:, success: status.success?)

          completed_processes, failed_bounded_child = update_bounded_child_state(
            completed_children: completed_processes,
            failed_bounded_child:,
            shutdown_controller:,
            status:
          )
        end
      end
    rescue StandardError
      cleanup_tracked_children(child_pids)
      raise
    end

    private

    attr_reader :child_worker_class, :configuration, :queue_store, :runtime

    def spawn_missing_children(child_pids, desired_children, shutdown_controller)
      while shutdown_controller.normal? && child_pids.length < desired_children
        pid = runtime.fork_child do
          SIGNALS.each do |signal_name|
            Signal.trap(signal_name, 'DEFAULT')
          end
          run_child_worker
        end
        normalized_pid = Pid.new(pid).normalize
        child_pids[normalized_pid] = true
        instrument('supervisor.child.spawned', pid: normalized_pid)
      end
    end

    def desired_child_count(shutdown_controller, completed_children)
      process_count = configuration.processes
      return 0 unless shutdown_controller.normal?
      return process_count unless configuration.bounded_run?

      process_count - completed_children
    end

    def signal_children_for_shutdown(child_pids:, shutdown_controller:, graceful_signal_sent:, forced_signal_sent:)
      pids = child_pids.keys
      if shutdown_controller.draining? && !graceful_signal_sent
        signal_children(pids, GRACEFUL_SIGNAL)
        graceful_signal_sent = true
      end

      if shutdown_controller.force_stop? && !forced_signal_sent
        signal_children(pids, FORCEFUL_SIGNAL)
        forced_signal_sent = true
      end

      [graceful_signal_sent, forced_signal_sent]
    end

    def signal_children(pids, signal)
      instrument('supervisor.shutdown.signal_forwarded', signal:, pids:)
      pids.each do |pid|
        runtime.kill_process(signal, pid)
      rescue Errno::ESRCH
        nil
      end
    end

    def bounded_child_exit?(shutdown_controller)
      shutdown_controller.normal? && configuration.bounded_run?
    end

    def update_bounded_child_state(completed_children:, failed_bounded_child:, shutdown_controller:, status:)
      return [completed_children, failed_bounded_child] unless bounded_child_exit?(shutdown_controller)

      [completed_children + 1, failed_bounded_child || !status.success?]
    end

    def run_child_worker
      ChildProcessRunner.new(
        child_worker_class:,
        configuration:,
        queue_store:,
        signal_subscriber: runtime.signal_subscriber
      ).run
    end

    def with_signal_handlers(shutdown_controller)
      restorers = []
      register_signal_restorers(restorers, shutdown_controller)
      yield
    ensure
      restorers ||= []
      restorers.reverse_each(&:call)
    end

    def register_signal_restorers(restorers, shutdown_controller)
      SIGNALS.each do |signal|
        restorers << runtime.subscribe_signal(signal, -> { shutdown_controller.advance })
      end
    end

    def cleanup_tracked_children(child_pids)
      shutdown_tracked_children(child_pids, GRACEFUL_SIGNAL, blocking: false)
      return if child_pids.empty?

      shutdown_tracked_children(child_pids, FORCEFUL_SIGNAL, blocking: true)
    end

    def shutdown_tracked_children(child_pids, signal, blocking:)
      signal_children(child_pids.keys, signal)
      reap_tracked_children(child_pids) { blocking ? runtime.wait_for_child : runtime.poll_for_child_exit }
    end

    def reap_tracked_children(child_pids)
      loop do
        return if child_pids.empty?

        waited_child = yield
        return unless waited_child

        pid, = waited_child
        child_pids.delete(pid)
      end
    end

    def raise_unknown_option_error(options)
      raise InvalidWorkerSupervisorConfigurationError,
            "unknown runtime dependency keywords: #{options.keys.join(', ')}"
    end

    def instrument(event, **payload)
      runtime.instrument(event, payload.merge(worker_id: configuration.worker_id))
    end

    private_constant :Configuration,
                     :ChildProcessRunner,
                     :FORCEFUL_SIGNAL,
                     :GRACEFUL_SIGNAL,
                     :HandlerMapping,
                     :MaxIterationsSetting,
                     :NOOP_SUBSCRIPTION,
                     :Pid,
                     :Runtime,
                     :ShutdownController,
                     :SIGNALS
  end
end
