# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'monitor'
require_relative 'base'
require_relative 'job_lifecycle'
require_relative 'worker'
require_relative 'internal/runtime_support/signal_restorer'
require_relative 'internal/runtime_support/iteration_limit'
require_relative 'internal/runtime_support/shutdown_state'
require_relative 'primitives/lifecycle'
require_relative 'primitives/identifier'
require_relative 'primitives/queue_list'
require_relative 'primitives/positive_finite_number'
require_relative 'primitives/non_negative_finite_number'
require_relative 'primitives/callable'
require_relative 'primitives/optional_callable'
require_relative 'primitives/positive_integer'
require_relative 'worker_supervisor/configuration'
require_relative 'worker_supervisor/handler_mapping'
require_relative 'worker_supervisor/max_iterations_setting'
require_relative 'worker_supervisor/pid'
require_relative 'worker_supervisor/runtime'
require_relative 'worker_supervisor/runtime_snapshot'
require_relative 'worker_supervisor/runtime_state_store'
require_relative 'worker_supervisor/runtime_control_server'
require_relative 'worker_supervisor/child_process_runner'
require_relative 'worker_supervisor/run_session'
require_relative 'worker_supervisor/shutdown_controller'

module Karya
  # Raised when worker supervisor bootstrap input is invalid.
  class InvalidWorkerSupervisorConfigurationError < Error; end

  # Supervisor process that manages forked worker children.
  # :reek:TooManyMethods { enabled: false }
  # :reek:MissingSafeMethod { exclude: [validate_queue_store!] }
  class WorkerSupervisor
    # Encapsulates the out-of-band signal used only to interrupt blocking waits.
    class WakeupSignal
      def self.register_restorer(signal)
        previous_handler = Signal.trap(signal) { nil }
        -> { Signal.trap(signal, previous_handler) }
      end

      def self.interrupt(signal)
        Process.kill(signal, Process.pid)
      rescue Errno::ESRCH
        nil
      end
    end

    DEFAULT_PROCESSES = 1
    DEFAULT_THREADS = 1
    FORCEFUL_SIGNAL = 'KILL'
    GRACEFUL_SIGNAL = 'TERM'
    NOOP_SUBSCRIPTION = -> {}.freeze
    WAKEUP_SIGNAL = 'USR1'
    SIGNALS = %w[INT TERM].freeze

    def initialize(queue_store: nil, **attributes)
      extracted_options = attributes.dup
      @queue_store = queue_store
      validate_queue_store!
      configuration = extracted_options.delete(:configuration)
      runtime = extracted_options.delete(:runtime)
      @configuration = configuration || Configuration.from_options(extracted_options)
      @runtime = runtime || Runtime.from_options(extracted_options)
      @child_worker_class = extracted_options.delete(:child_worker_class) || Worker
      runtime_state_store = extracted_options.delete(:runtime_state_store)
      state_file = extracted_options.delete(:state_file)
      @runtime_state_store = runtime_state_store || RuntimeStateStore.new(configuration: @configuration, path: state_file)
      @control_monitor = Monitor.new
      @run_session = nil
      @runtime_control_server = nil
      @running_claimed = false
      @shutdown_controller = nil
      raise_unknown_option_error(extracted_options) unless extracted_options.empty?
    end

    def runtime_snapshot
      runtime_state_store.snapshot
    end

    def begin_drain
      with_running_session(&:request_drain)
    end

    def force_stop
      with_running_session(&:request_force_stop)
    end

    def run
      shutdown_controller = ShutdownController.new
      assign_shutdown_controller(shutdown_controller)
      run_session = nil

      with_signal_handlers(shutdown_controller) do
        run_session = prepare_run(shutdown_controller)
        run_result = run_session.call
        finalize_run(run_result)
      rescue StandardError
        cleanup_tracked_children(run_session&.child_pids || {})
        raise
      ensure
        release_run
      end
    end

    private

    attr_reader :child_worker_class, :configuration, :control_monitor, :queue_store, :runtime, :runtime_state_store

    def validate_queue_store!
      return if @queue_store

      raise InvalidWorkerSupervisorConfigurationError, 'queue_store is required'
    end

    def prepare_run(shutdown_controller)
      @run_session = RunSession.new(supervisor: self, shutdown_controller:)
      runtime_state_store.write_running
      @running_claimed = true
      @runtime_control_server = RuntimeControlServer.new(
        path: runtime_state_store.control_socket_path,
        instance_token: runtime_state_store.instance_token,
        command_handler: method(:handle_runtime_control_command),
        logger: Karya.logger
      ).start
      @run_session
    end

    def release_run
      runtime_control_server = nil
      running_claimed = false

      control_monitor.synchronize do
        runtime_control_server = @runtime_control_server
        running_claimed = @running_claimed
        @run_session = nil
        @runtime_control_server = nil
        @running_claimed = false
        @shutdown_controller = nil
      end

      runtime_control_server&.stop
      mark_runtime_stopped if running_claimed
    end

    def finalize_run(run_result)
      run_result
    end

    def spawn_missing_children(child_pids, desired_children, shutdown_controller)
      while shutdown_controller.normal? && child_pids.length < desired_children
        pid = runtime.fork_child do
          (SIGNALS + [WAKEUP_SIGNAL]).each do |signal_name|
            Signal.trap(signal_name, 'DEFAULT')
          end
          run_child_worker
        end
        normalized_pid = Pid.new(pid).normalize
        child_pids[normalized_pid] = true
        runtime_state_store.register_child(normalized_pid)
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
      state = signal == FORCEFUL_SIGNAL ? RuntimeStateStore::CHILD_FORCE_STOPPING_STATE : RuntimeStateStore::CHILD_DRAINING_STATE
      pids.each do |pid|
        runtime_state_store.mark_child_phase(pid, state)
        runtime.kill_process(signal, pid)
      rescue Errno::ESRCH
        nil
      end
    end

    def bounded_child_exit?(shutdown_controller)
      shutdown_controller.normal? && configuration.bounded_run?
    end

    def prune_stale_children(child_pids)
      pruned_children = 0
      child_pids.delete_if do |pid, _|
        pruned = !runtime.process_alive?(pid)
        pruned_children += 1 if pruned
        pruned
      end
      pruned_children
    end

    def update_bounded_child_state(completed_children:, failed_bounded_child:, shutdown_controller:, status:)
      return [completed_children, failed_bounded_child] unless bounded_child_exit?(shutdown_controller)

      [completed_children + 1, failed_bounded_child || !status.success?]
    end

    def update_pruned_child_state(completed_children:, failed_bounded_child:, pruned_children:, shutdown_controller:)
      return [completed_children, failed_bounded_child] if pruned_children.zero?
      return [completed_children, failed_bounded_child] unless bounded_child_exit?(shutdown_controller)

      [completed_children + pruned_children, true]
    end

    def run_child_worker
      ChildProcessRunner.new(
        child_worker_class:,
        configuration:,
        queue_store:,
        signal_subscriber: runtime.signal_subscriber,
        runtime_state_store:
      ).run
    end

    def with_signal_handlers(shutdown_controller)
      restorers = []
      collect_signal_restorers(restorers, shutdown_controller)
      yield
    ensure
      Array(restorers).reverse_each(&:call)
    end

    def collect_signal_restorers(restorers, shutdown_controller)
      register_signal_restorers(restorers, shutdown_controller)
      restorers << WakeupSignal.register_restorer(WAKEUP_SIGNAL)
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
      reap_tracked_children(child_pids, blocking:) { blocking ? runtime.wait_for_child : runtime.poll_for_child_exit }
    end

    def reap_tracked_children(child_pids, blocking:)
      while child_pids.any?
        waited_child = yield
        unless waited_child
          prune_stale_children(child_pids)
          return if child_pids.empty? || !blocking

          next
        end

        pid, = waited_child
        child_pids.delete(pid)
      end
    end

    def raise_unknown_option_error(options)
      raise InvalidWorkerSupervisorConfigurationError,
            "unknown keyword options: #{options.keys.join(', ')}"
    end

    def with_running_session
      control_monitor.synchronize do
        run_session = @run_session
        snapshot = runtime_state_store.snapshot if run_session
        running = run_session && snapshot.phase != RuntimeStateStore::STOPPED_PHASE
        raise RuntimeControlUnavailableError, 'worker supervisor is not running' unless running

        yield(run_session)
      end
    end

    def assign_shutdown_controller(shutdown_controller)
      control_monitor.synchronize { @shutdown_controller = shutdown_controller }
    end

    def handle_runtime_control_command(command)
      case command
      when 'drain'
        begin_drain
      when 'force_stop'
        force_stop
      else
        raise InvalidRuntimeStateFileError, "unsupported runtime control command: #{command}"
      end
    end

    def mark_runtime_stopped
      runtime_state_store.write_stopped
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
                     :RuntimeControlServer,
                     :RunSession,
                     :ShutdownController,
                     :SIGNALS,
                     :WakeupSignal,
                     :WAKEUP_SIGNAL
  end
end
