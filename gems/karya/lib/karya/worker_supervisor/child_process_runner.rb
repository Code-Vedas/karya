# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class WorkerSupervisor
    # Runs the child-process thread pool using a shared shutdown controller.
    class ChildProcessRunner
      NOOP_SUBSCRIPTION = -> {}.freeze
      SIGNALS = %w[INT TERM].freeze

      def initialize(child_worker_class:, configuration:, queue_store:, signal_subscriber:, runtime_state_store: RuntimeStateStore::NullStore.new)
        @child_worker_class = child_worker_class
        @configuration = configuration
        @queue_store = queue_store
        @signal_subscriber = signal_subscriber
        @runtime_state_store = runtime_state_store
      end

      def run
        shutdown_controller = ShutdownController.new
        with_signal_handlers(shutdown_controller) do
          failures = Queue.new
          threads = build_threads(shutdown_controller, failures)
          threads.each(&:join)
          raise failures.pop unless failures.empty?
        end
      end

      private

      attr_reader :child_worker_class, :configuration, :queue_store, :runtime_state_store, :signal_subscriber

      def build_threads(shutdown_controller, failures)
        Array.new(configuration.threads) do |index|
          Thread.new do
            run_thread_worker(index + 1, shutdown_controller)
          rescue StandardError => e
            shutdown_controller.advance until shutdown_controller.force_stop?
            failures << e
          end
        end
      end

      def run_thread_worker(thread_index, shutdown_controller)
        process_pid = Process.pid
        worker_id = child_worker_id(thread_index)
        runtime_state_store.register_thread(process_pid:, worker_id:, thread_index:)
        worker = child_worker_class.new(
          queue_store:,
          worker_id:,
          queues: configuration.queues,
          handlers: configuration.handlers,
          lease_duration: configuration.lease_duration,
          lifecycle: configuration.lifecycle,
          default_execution_timeout: configuration.default_execution_timeout,
          state_reporter: method(:report_thread_state)
        )
        worker.run(
          poll_interval: configuration.poll_interval,
          max_iterations: child_max_iterations,
          stop_when_idle: configuration.stop_when_idle,
          shutdown_controller:
        )
      ensure
        mark_thread_stopped(process_pid:, worker_id:)
      end

      def child_worker_id(thread_index)
        "#{configuration.worker_id}:#{Process.pid}:thread-#{thread_index}"
      end

      def child_max_iterations
        max_iterations = configuration.max_iterations
        max_iterations == :unlimited ? nil : max_iterations
      end

      def with_signal_handlers(shutdown_controller)
        restorers = collect_signal_restorers(shutdown_controller)
        yield
      ensure
        restorers ||= []
        restorers.reverse_each(&:call)
      end

      def collect_signal_restorers(shutdown_controller)
        restorers = []
        append_signal_restorers(restorers, shutdown_controller)
        restorers
      end

      def append_signal_restorers(restorers, shutdown_controller)
        SIGNALS.each do |signal|
          restorers << subscribe_signal(signal, -> { shutdown_controller.advance })
        end
      end

      def subscribe_signal(signal, handler)
        return NOOP_SUBSCRIPTION unless signal_subscriber

        restorer = signal_subscriber.call(signal, handler)
        Internal::RuntimeSupport::SignalRestorer.new(
          { nil => NOOP_SUBSCRIPTION }.fetch(restorer, restorer),
          error_class: InvalidWorkerSupervisorConfigurationError,
          message: "signal_subscriber must return a callable restorer responding to #call, got: #{restorer.inspect}"
        ).normalize
      end

      def report_thread_state(worker_id:, state:)
        runtime_state_store.mark_thread_state(process_pid: Process.pid, worker_id:, state:)
      end

      def mark_thread_stopped(process_pid:, worker_id:)
        runtime_state_store.mark_thread_state(process_pid:, worker_id:, state: RuntimeStateStore::THREAD_STOPPED_STATE)
      rescue StandardError => e
        Karya.logger.error(
          'runtime state reporting failed during child thread shutdown',
          process_pid:,
          worker_id:,
          error_class: e.class.name,
          error_message: e.message
        )
        nil
      end
    end
  end
end
