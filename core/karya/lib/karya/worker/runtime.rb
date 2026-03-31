# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Worker
    # Worker runtime dependencies that provide clock and sleep behavior.
    class Runtime
      OPTION_KEYS = %i[clock instrumenter logger signal_subscriber sleeper].freeze

      attr_reader :instrumenter, :logger

      def self.from_options(options)
        attributes = OPTION_KEYS.each_with_object({}) do |key, collected|
          collected[key] = options.delete(key) if options.key?(key)
        end
        new(**attributes)
      end

      def initialize(clock: -> { Time.now.utc }, instrumenter: nil, logger: nil, sleeper: nil, signal_subscriber: nil)
        @clock = Primitives::Callable.new(:clock, clock, error_class: InvalidWorkerConfigurationError).normalize
        @instrumenter = Primitives::OptionalCallable.new(:instrumenter, instrumenter || Karya.instrumenter,
                                                         error_class: InvalidWorkerConfigurationError).normalize
        @logger = logger || Karya.logger
        @sleeper = Primitives::Callable.new(:sleeper, sleeper || lambda { |duration|
          Kernel.sleep(duration)
        }, error_class: InvalidWorkerConfigurationError).normalize
        @signal_subscriber = Primitives::OptionalCallable.new(:signal_subscriber, signal_subscriber, error_class: InvalidWorkerConfigurationError).normalize
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
          restorer || NOOP_SUBSCRIPTION,
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
    end
  end
end
