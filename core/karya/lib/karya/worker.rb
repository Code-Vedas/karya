# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  # Raised when worker bootstrap input is invalid.
  class InvalidWorkerConfigurationError < Error; end

  # Raised when a reserved job cannot be mapped to executable code.
  class MissingHandlerError < Error; end

  # Single-process worker that reserves jobs, dispatches handlers, and persists outcomes.
  class Worker
    DEFAULT_POLL_INTERVAL = 1

    def initialize(queue_store:, configuration: nil, runtime: nil, **options)
      extracted_options = options.dup
      @queue_store = queue_store
      @configuration = configuration || Configuration.from_options(extracted_options)
      @runtime = runtime || Runtime.from_options(extracted_options)
      raise_unknown_option_error(extracted_options) unless extracted_options.empty?
    end

    def worker_id
      configuration.worker_id
    end

    def queues
      configuration.queues
    end

    def handlers
      configuration.handlers
    end

    def lease_duration
      configuration.lease_duration
    end

    def work_once
      reservation = reserve_next
      return nil unless reservation

      reservation_token = reservation.token
      running_job = queue_store.start_execution(reservation_token:, now: current_time)

      begin
        handlers.fetch(running_job.handler).call(arguments: running_job.arguments)
        queue_store.complete_execution(reservation_token:, now: current_time)
      rescue StandardError
        queue_store.fail_execution(reservation_token:, now: current_time)
      end
    end

    def run(poll_interval: DEFAULT_POLL_INTERVAL, max_iterations: nil, stop_when_idle: false)
      normalized_poll_interval = NonNegativeFiniteNumber.new(:poll_interval, poll_interval).normalize
      iteration_limit = IterationLimit.new(max_iterations)
      iterations = 0

      loop do
        result = work_once
        iterations += 1
        idle = !result

        return result if stop_when_idle && idle
        return result if iteration_limit.reached?(iterations)

        runtime.sleep(normalized_poll_interval) if idle && normalized_poll_interval.positive?
      end
    end

    private

    attr_reader :configuration, :queue_store, :runtime

    def reserve_next
      queues.each do |queue|
        reservation = queue_store.reserve(
          queue:,
          worker_id:,
          lease_duration:,
          now: current_time
        )
        return reservation if reservation
      end

      nil
    end

    def current_time
      runtime.current_time
    end

    def raise_unknown_option_error(options)
      raise InvalidWorkerConfigurationError, "unknown runtime dependency keywords: #{options.keys.join(', ')}"
    end

    # Validated worker bootstrap configuration.
    class Configuration
      OPTION_KEYS = %i[worker_id queues handlers lease_duration].freeze

      def self.from_options(options)
        attributes = OPTION_KEYS.each_with_object({}) do |key, collected|
          collected[key] = options.delete(key) if options.key?(key)
        end
        new(**attributes)
      end

      attr_reader :handlers, :lease_duration, :queues, :worker_id

      def initialize(worker_id:, queues:, handlers:, lease_duration:)
        @worker_id = Identifier.new(:worker_id, worker_id).normalize
        @queues = QueueList.new(queues).normalize
        @handlers = HandlerRegistry.new(handlers).normalize
        @lease_duration = PositiveFiniteNumber.new(:lease_duration, lease_duration).normalize
      end
    end

    # Worker runtime dependencies that provide clock and sleep behavior.
    class Runtime
      OPTION_KEYS = %i[clock sleeper].freeze

      def self.from_options(options)
        attributes = OPTION_KEYS.each_with_object({}) do |key, collected|
          collected[key] = options.delete(key) if options.key?(key)
        end
        new(**attributes)
      end

      def initialize(clock: -> { Time.now.utc }, sleeper: nil)
        @clock = Callable.new(:clock, clock).normalize
        @sleeper = sleeper || ->(duration) { Kernel.sleep(duration) }
      end

      def current_time
        value = @clock.call
        raise InvalidWorkerConfigurationError, 'clock must return a Time' unless value.is_a?(Time)

        value
      end

      def sleep(duration)
        @sleeper.call(duration)
      end
    end

    # Normalizes identifier-like values into non-blank strings.
    class Identifier
      def initialize(name, value)
        @name = name
        @value = value
      end

      def normalize
        normalized_value = value.to_s.strip
        return normalized_value unless normalized_value.empty?

        raise InvalidWorkerConfigurationError, "#{name} must be present"
      end

      private

      attr_reader :name, :value
    end

    # Normalizes queue lists into a frozen list of queue identifiers.
    class QueueList
      def initialize(values)
        @values = values
      end

      def normalize
        normalized_values = Array(values).map { |value| Identifier.new(:queue, value).normalize }
        raise InvalidWorkerConfigurationError, 'queues must be present' if normalized_values.empty?

        normalized_values.freeze
      end

      private

      attr_reader :values
    end

    # Normalizes handler mappings into executable handler entries.
    class HandlerRegistry
      def initialize(value)
        @value = value
      end

      def normalize
        raise InvalidWorkerConfigurationError, 'handlers must be a Hash' unless value.is_a?(Hash)

        value.each_with_object({}) do |(name, handler), normalized|
          normalized_name = Identifier.new(:handler, name).normalize
          normalized[normalized_name] = HandlerExecution.build(handler:, handler_name: normalized_name)
        end.freeze
      end

      private

      attr_reader :value
    end

    # Validates positive, finite numeric values.
    class PositiveFiniteNumber
      def initialize(name, value)
        @name = name
        @value = value
      end

      def normalize
        return value if valid?

        raise InvalidWorkerConfigurationError, "#{name} must be a positive finite number"
      end

      private

      attr_reader :name, :value

      def valid?
        value.is_a?(Numeric) && value.positive? && (!value.is_a?(Float) || value.finite?)
      end
    end

    # Validates non-negative, finite numeric values.
    class NonNegativeFiniteNumber
      def initialize(name, value)
        @name = name
        @value = value
      end

      def normalize
        return value if valid?

        raise InvalidWorkerConfigurationError, "#{name} must be a finite non-negative number"
      end

      private

      attr_reader :name, :value

      def valid?
        value.is_a?(Numeric) && value >= 0 && (!value.is_a?(Float) || value.finite?)
      end
    end

    # Validates callable dependencies such as worker clocks.
    class Callable
      def initialize(name, value)
        @name = name
        @value = value
      end

      def normalize
        value.public_method(:call)
        value
      rescue NameError
        raise InvalidWorkerConfigurationError, "#{name} must respond to #call"
      end

      private

      attr_reader :name, :value
    end

    # Encapsulates optional max-iteration behavior for the worker run loop.
    class IterationLimit
      NORMALIZERS = {
        Integer => lambda do |candidate|
          return candidate if candidate.positive?

          raise InvalidWorkerConfigurationError, 'max_iterations must be a positive Integer'
        end,
        NilClass => ->(_candidate) { :unlimited }
      }.freeze

      def initialize(value)
        @value = normalize(value)
      end

      def reached?(iterations)
        return false if value == :unlimited

        iterations >= value
      end

      private

      attr_reader :value

      def normalize(candidate)
        normalizer = NORMALIZERS[candidate.class]
        return normalizer.call(candidate) if normalizer

        raise InvalidWorkerConfigurationError, 'max_iterations must be a positive Integer'
      end
    end

    # Converts normalized job arguments into Ruby keyword arguments for handler dispatch.
    class KeywordArguments
      def self.normalize(arguments)
        arguments.each_with_object({}) do |(key, value), normalized|
          normalized[key.to_sym] = value
        end
      end

      private_class_method :new
    end

    # Builds executable handler entries from registered runtime handlers.
    class HandlerExecution
      def self.build(handler:, handler_name:)
        return CallableExecution.new(handler) if callable?(handler)
        return PerformExecution.new(handler) if performable?(handler)

        UnsupportedExecution.new(handler_name)
      end

      def self.callable?(handler)
        handler.public_method(:call)
        true
      rescue NameError
        false
      end

      def self.performable?(handler)
        handler.public_method(:perform)
        true
      rescue NameError
        false
      end
    end

    # Executes handlers that respond to `call`.
    class CallableExecution
      def initialize(handler)
        @handler = handler
      end

      def call(arguments:)
        @handler.call(**KeywordArguments.normalize(arguments))
      end
    end

    # Executes handlers that respond to `perform`.
    class PerformExecution
      def initialize(handler)
        @handler = handler
      end

      def call(arguments:)
        @handler.perform(**KeywordArguments.normalize(arguments))
      end
    end

    # Raises a configuration error when the registered handler is not executable.
    class UnsupportedExecution
      def initialize(handler_name)
        @handler_name = handler_name
      end

      def call(arguments:)
        _arguments = arguments
        raise InvalidWorkerConfigurationError, "handler #{@handler_name.inspect} must respond to #call or #perform"
      end
    end
  end
end
