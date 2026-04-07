# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Worker
    # Worker runtime dependencies that provide clock and sleep behavior.
    class Runtime
      OPTION_KEYS = %i[clock instrumenter logger signal_subscriber sleeper state_reporter].freeze
      UNSET = Object.new.freeze

      attr_reader :instrumenter, :logger

      def self.from_options(options)
        attributes = OPTION_KEYS.each_with_object({}) do |key, collected|
          collected[key] = options.delete(key) if options.key?(key)
        end
        new(**attributes)
      end

      def initialize(**attributes)
        clock = attributes.fetch(:clock, -> { Time.now.utc })
        instrumenter = attributes.fetch(:instrumenter, UNSET)
        logger = attributes.fetch(:logger, UNSET)
        sleeper = attributes.fetch(:sleeper, UNSET)
        signal_subscriber = attributes.fetch(:signal_subscriber, nil)
        state_reporter = attributes.fetch(:state_reporter, nil)

        @clock = Primitives::Callable.new(:clock, clock, error_class: InvalidWorkerConfigurationError).normalize
        @instrumenter = Primitives::OptionalCallable.new(
          :instrumenter,
          instrumenter.equal?(UNSET) ? Karya.instrumenter : instrumenter,
          error_class: InvalidWorkerConfigurationError
        ).normalize
        @logger = validate_logger(logger.equal?(UNSET) ? Karya.logger : logger)
        @sleeper = Primitives::Callable.new(
          :sleeper,
          sleeper.equal?(UNSET) ? default_sleeper : sleeper,
          error_class: InvalidWorkerConfigurationError
        ).normalize
        @signal_subscriber = Primitives::OptionalCallable.new(:signal_subscriber, signal_subscriber, error_class: InvalidWorkerConfigurationError).normalize
        @state_reporter = Primitives::OptionalCallable.new(:state_reporter, state_reporter, error_class: InvalidWorkerConfigurationError).normalize
      end

      def current_time
        value = @clock.call
        raise InvalidWorkerConfigurationError, 'clock must return a Time' unless value.is_a?(Time)

        value
      end

      def sleep(duration)
        @sleeper.call(duration)
      end

      def subscribe_signal(signal, handler)
        return NOOP_SUBSCRIPTION unless @signal_subscriber

        restorer = @signal_subscriber.call(signal, handler)
        Internal::RuntimeSupport::SignalRestorer.new(
          { nil => NOOP_SUBSCRIPTION }.fetch(restorer, restorer),
          error_class: InvalidWorkerConfigurationError,
          message: 'signal_subscriber must return a callable (responding to #call) or nil'
        ).normalize
      end

      def instrument(event, payload)
        return unless instrumenter

        instrumenter.call(event, payload)
      rescue StandardError => e
        logger.error('instrumentation failed', event:, error_class: e.class.name, error_message: e.message)
        nil
      end

      def report_state(worker_id:, state:)
        return unless @state_reporter

        @state_reporter.call(worker_id:, state:)
      rescue StandardError => e
        logger.error('runtime state reporting failed', worker_id:, state:, error_class: e.class.name, error_message: e.message)
        nil
      end

      private

      def default_sleeper
        lambda do |duration|
          Kernel.sleep(duration)
        end
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
