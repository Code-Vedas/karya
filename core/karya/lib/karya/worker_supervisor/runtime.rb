# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../internal/hook_dispatch'
require_relative '../internal/immutable_hook_payload'
require_relative '../internal/payload_input'

module Karya
  class WorkerSupervisor
    # Supervisor runtime hooks for process management and signal handling.
    class Runtime
      OPTION_KEYS = %i[forker instrumenter killer logger outbound_event_dispatcher poll_waiter signal_subscriber waiter].freeze
      UNSET = Object.new.freeze

      attr_reader :instrumenter, :logger, :outbound_event_dispatcher, :signal_subscriber

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

      def self.normalize_forker(name, value)
        Primitives::Forker.new(name, value, error_class: InvalidWorkerSupervisorConfigurationError).normalize
      end

      def self.normalize_optional_callable(name, value)
        Primitives::OptionalCallable.new(name, value, error_class: InvalidWorkerSupervisorConfigurationError).normalize
      end

      def self.normalize_optional_outbound_event_dispatcher(name, value)
        Primitives::OptionalOutboundEventDispatcher.new(
          name,
          value,
          error_class: InvalidWorkerSupervisorConfigurationError
        ).normalize
      end

      def self.resolve_option(attributes, key, default:)
        value = attributes.fetch(key, UNSET)
        value.equal?(UNSET) ? default : value
      end

      def initialize(**attributes)
        @process_liveness = lambda do |pid|
          Process.kill(0, pid)
          true
        rescue Errno::EPERM
          true
        rescue Errno::ESRCH
          false
        end
        runtime_class = self.class
        @forker = runtime_class.normalize_forker(
          :forker,
          runtime_class.resolve_option(attributes, :forker, default: method(:default_forker))
        )
        @instrumenter = runtime_class.normalize_optional_callable(
          :instrumenter,
          runtime_class.resolve_option(attributes, :instrumenter, default: Karya.instrumenter)
        )
        @killer = runtime_class.normalize_callable(
          :killer,
          runtime_class.resolve_option(attributes, :killer, default: runtime_class.default_killer)
        )
        @logger = validate_logger(
          runtime_class.resolve_option(attributes, :logger, default: Karya.logger)
        )
        @outbound_event_dispatcher = runtime_class.normalize_optional_outbound_event_dispatcher(
          :outbound_event_dispatcher,
          runtime_class.resolve_option(attributes, :outbound_event_dispatcher, default: Karya.outbound_event_dispatcher)
        )
        @poll_waiter = runtime_class.normalize_callable(
          :poll_waiter,
          runtime_class.resolve_option(attributes, :poll_waiter, default: default_poll_waiter)
        )
        @signal_subscriber = runtime_class.normalize_optional_callable(
          :signal_subscriber,
          runtime_class.resolve_option(attributes, :signal_subscriber, default: nil)
        )
        @waiter = runtime_class.normalize_callable(
          :waiter,
          runtime_class.resolve_option(attributes, :waiter, default: default_waiter)
        )
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
          { nil => NOOP_SUBSCRIPTION }.fetch(restorer, restorer),
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

      def instrument(event, payload = Internal::PayloadInput::ABSENT, **payload_keywords)
        dispatch_outbound = outbound_dispatcher_supports_event?(event)
        payload_given = !payload.equal?(Internal::PayloadInput::ABSENT)
        Internal::HookDispatch.instrument(
          event:,
          payload: payload_given ? payload : nil,
          payload_keywords:,
          payload_given:,
          error_class: InvalidWorkerSupervisorConfigurationError,
          instrumenter:,
          dispatch_outbound:,
          mixed_payload_message: 'payload must be a Hash when keyword payload is also given',
          emit_instrumentation: method(:emit_instrumentation),
          emit_outbound_event: method(:emit_outbound_event)
        )
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

      private

      def validate_logger(value)
        %i[debug info warn error].each do |level|
          value.public_method(level)
        end
        value
      rescue NameError
        raise InvalidWorkerSupervisorConfigurationError, 'logger must respond to #debug, #info, #warn, and #error'
      end

      def emit_instrumentation(event, payload)
        return unless instrumenter

        instrumenter.call(event, payload)
      rescue StandardError => e
        logger.error('instrumentation failed', event:, error_class: e.class.name, error_message: e.message)
        nil
      end

      def emit_outbound_event(event, payload)
        return unless outbound_event_dispatcher

        outbound_event_dispatcher.call(event, payload)
      rescue UnsupportedOutboundEventError
        nil
      rescue StandardError => e
        logger.error('outbound event dispatch failed', event:, error_class: e.class.name, error_message: e.message)
        nil
      end

      def outbound_dispatcher_supports_event?(event)
        return false unless outbound_event_dispatcher
        return Karya::OutboundEvents::SchemaCatalog.supported?(event) if built_in_outbound_event_dispatcher?

        true
      end

      def built_in_outbound_event_dispatcher?
        defined?(Karya::OutboundEvents::Dispatcher) && outbound_event_dispatcher.is_a?(Karya::OutboundEvents::Dispatcher)
      end

      private_constant :UNSET
    end
  end
end
