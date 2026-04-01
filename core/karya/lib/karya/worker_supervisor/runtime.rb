# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class WorkerSupervisor
    # Supervisor runtime hooks for process management and signal handling.
    class Runtime
      OPTION_KEYS = %i[forker instrumenter killer logger poll_waiter signal_subscriber waiter].freeze

      attr_reader :instrumenter, :logger, :signal_subscriber

      def self.from_options(options)
        attributes = OPTION_KEYS.each_with_object({}) do |key, collected|
          collected[key] = options.delete(key) if options.key?(key)
        end
        new(**attributes)
      end

      def self.default_killer
        ->(signal, pid) { Process.kill(signal, pid) }
      end

      def self.normalize_callable(name, value)
        Primitives::Callable.new(name, value, error_class: InvalidWorkerSupervisorConfigurationError).normalize
      end

      def self.normalize_optional_callable(name, value)
        Primitives::OptionalCallable.new(name, value, error_class: InvalidWorkerSupervisorConfigurationError).normalize
      end

      def initialize(**attributes)
        runtime_class = self.class
        @process_liveness = lambda do |pid|
          Process.kill(0, pid)
          true
        rescue Errno::EPERM
          true
        rescue Errno::ESRCH
          false
        end
        @forker = runtime_class.normalize_callable(:forker, attributes.fetch(:forker, nil) || method(:default_forker))
        @instrumenter = runtime_class.normalize_optional_callable(:instrumenter, attributes.fetch(:instrumenter, nil) || Karya.instrumenter)
        @killer = runtime_class.normalize_callable(:killer, attributes.fetch(:killer, nil) || runtime_class.default_killer)
        @logger = attributes.fetch(:logger, nil) || Karya.logger
        @poll_waiter = runtime_class.normalize_callable(:poll_waiter, attributes.fetch(:poll_waiter, nil) || default_poll_waiter)
        @signal_subscriber = runtime_class.normalize_optional_callable(:signal_subscriber, attributes.fetch(:signal_subscriber, nil))
        @waiter = runtime_class.normalize_callable(:waiter, attributes.fetch(:waiter, nil) || default_waiter)
      end

      def fork_child(&)
        @forker.call(&)
      end

      def kill_process(signal, pid)
        @killer.call(signal, pid)
      end

      def process_alive?(pid)
        @process_liveness.call(pid)
      end

      def subscribe_signal(signal, handler)
        return NOOP_SUBSCRIPTION unless signal_subscriber

        restorer = signal_subscriber.call(signal, handler)
        Internal::RuntimeSupport::SignalRestorer.new(
          restorer || NOOP_SUBSCRIPTION,
          error_class: InvalidWorkerSupervisorConfigurationError,
          message: "signal_subscriber must return a callable restorer responding to #call, got: #{restorer.inspect}"
        ).normalize
      end

      def wait_for_child
        @waiter.call
      end

      def poll_for_child_exit
        @poll_waiter.call
      end

      def instrument(event, payload)
        return unless instrumenter

        instrumenter.call(event, payload)
      rescue StandardError => e
        logger.error('instrumentation failed', event:, error_class: e.class.name, error_message: e.message)
        nil
      end

      # :nocov:
      def default_forker(&)
        Process.fork do
          yield
          Kernel.exit!(0)
        rescue SystemExit
          raise
        rescue StandardError
          Kernel.exit!(1)
        end
      end
      # :nocov:

      def default_poll_waiter
        lambda do
          Process.wait2(-1, Process::WNOHANG)
        rescue Errno::EINTR
          retry
        rescue Errno::ECHILD
          nil
        end
      end

      def default_waiter
        lambda do
          Process.wait2(-1)
        rescue Errno::EINTR, Errno::ECHILD
          # Return control to the run loop so shutdown handling can proceed.
          nil
        end
      end
    end
  end
end
