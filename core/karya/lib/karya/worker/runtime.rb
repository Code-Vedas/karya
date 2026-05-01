# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../internal/payload_input'

module Karya
  class Worker
    # Worker runtime dependencies that provide clock and sleep behavior.
    class Runtime
      OPTION_KEYS = %i[clock instrumenter logger outbound_event_dispatcher signal_subscriber sleeper state_reporter].freeze
      UNSET = Object.new.freeze

      attr_reader :instrumenter, :logger, :outbound_event_dispatcher

      def self.from_options(options)
        attributes = OPTION_KEYS.each_with_object({}) do |key, collected|
          collected[key] = options.delete(key) if options.key?(key)
        end
        new(**attributes)
      end

      def initialize(**attributes)
        unknown_keys = attributes.each_key.reject { |key| OPTION_KEYS.include?(key) }
        raise InvalidWorkerConfigurationError, "unknown runtime option(s): #{unknown_keys.map(&:inspect).join(', ')}" unless unknown_keys.empty?

        initialize_clock(attributes)
        initialize_instrumenter(attributes)
        initialize_outbound_event_dispatcher(attributes)
        initialize_logger_dependency(attributes)
        initialize_sleeper(attributes)
        initialize_signal_subscriber(attributes)
        initialize_state_reporter(attributes)
      end

      def current_time
        value = clock.call
        raise InvalidWorkerConfigurationError, 'clock must return a Time' unless value.is_a?(Time)

        value
      end

      def sleep(duration)
        sleeper.call(duration)
      end

      def subscribe_signal(signal, handler)
        return NOOP_SUBSCRIPTION unless signal_subscriber

        restorer = signal_subscriber.call(signal, handler)
        Internal::RuntimeSupport::SignalRestorer.new(
          { nil => NOOP_SUBSCRIPTION }.fetch(restorer, restorer),
          error_class: InvalidWorkerConfigurationError,
          message: 'signal_subscriber must return a callable (responding to #call) or nil'
        ).normalize
      end

      def instrument(event, payload = Internal::PayloadInput::ABSENT, **payload_keywords)
        payload_given = !payload.equal?(Internal::PayloadInput::ABSENT)
        normalized_payload = Internal::PayloadInput.new(
          payload_given ? payload : nil,
          payload_keywords,
          payload_given:,
          error_class: InvalidWorkerConfigurationError,
          mixed_payload_message: 'payload must be a Hash when keyword payload is also given'
        ).to_h
        dispatch_outbound = outbound_dispatcher_supports_event?(event)
        return nil unless instrumenter || dispatch_outbound

        if instrumenter && dispatch_outbound
          instrumentation_payload, outbound_payload = Internal::ImmutableHookPayload.snapshot_pair(normalized_payload)
          emit_instrumentation(event, instrumentation_payload)
          emit_outbound_event(event, outbound_payload)
          return nil
        end

        snapshot = Internal::ImmutableHookPayload.snapshot(normalized_payload)
        emit_instrumentation(event, snapshot) if instrumenter
        emit_outbound_event(event, snapshot) if dispatch_outbound
        nil
      end

      def report_state(worker_id:, state:)
        return unless state_reporter

        state_reporter.call(worker_id:, state:)
      rescue StandardError => e
        logger.error('runtime state reporting failed', worker_id:, state:, error_class: e.class.name, error_message: e.message)
        nil
      end

      private

      attr_reader :clock, :signal_subscriber, :sleeper, :state_reporter

      def initialize_clock(attributes)
        clock = attributes.fetch(:clock, -> { Time.now.utc })
        @clock = Primitives::Callable.new(:clock, clock, error_class: InvalidWorkerConfigurationError).normalize
      end

      def initialize_instrumenter(attributes)
        instrumenter = attributes.fetch(:instrumenter, UNSET)
        @instrumenter = Primitives::OptionalCallable.new(
          :instrumenter,
          instrumenter.equal?(UNSET) ? Karya.instrumenter : instrumenter,
          error_class: InvalidWorkerConfigurationError
        ).normalize
      end

      def initialize_logger_dependency(attributes)
        logger = attributes.fetch(:logger, UNSET)
        @logger = validate_logger(logger.equal?(UNSET) ? Karya.logger : logger)
      end

      def initialize_outbound_event_dispatcher(attributes)
        outbound_event_dispatcher = attributes.fetch(:outbound_event_dispatcher, UNSET)
        @outbound_event_dispatcher = Primitives::OptionalOutboundEventDispatcher.new(
          :outbound_event_dispatcher,
          outbound_event_dispatcher.equal?(UNSET) ? Karya.outbound_event_dispatcher : outbound_event_dispatcher,
          error_class: InvalidWorkerConfigurationError
        ).normalize
      end

      def initialize_sleeper(attributes)
        sleeper = attributes.fetch(:sleeper, UNSET)
        @sleeper = Primitives::Callable.new(
          :sleeper,
          sleeper.equal?(UNSET) ? default_sleeper : sleeper,
          error_class: InvalidWorkerConfigurationError
        ).normalize
      end

      def initialize_signal_subscriber(attributes)
        signal_subscriber = attributes.fetch(:signal_subscriber, nil)
        @signal_subscriber = Primitives::OptionalCallable.new(
          :signal_subscriber,
          signal_subscriber,
          error_class: InvalidWorkerConfigurationError
        ).normalize
      end

      def initialize_state_reporter(attributes)
        state_reporter = attributes.fetch(:state_reporter, nil)
        @state_reporter = Primitives::OptionalCallable.new(
          :state_reporter,
          state_reporter,
          error_class: InvalidWorkerConfigurationError
        ).normalize
      end

      def default_sleeper
        lambda do |duration|
          Kernel.sleep(duration)
        end
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

      def validate_logger(value)
        %i[debug info warn error].each do |level|
          value.public_method(level)
        end
        value
      rescue NameError
        raise InvalidWorkerConfigurationError, 'logger must respond to #debug, #info, #warn, and #error'
      end

      private_constant :UNSET
    end
  end
end
