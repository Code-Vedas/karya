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
    LEASE_LOST = Object.new
    NO_WORK_AVAILABLE = Object.new

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
      result = work_once_result
      case result
      when NO_WORK_AVAILABLE, LEASE_LOST
        nil
      else
        result
      end
    end

    def run(poll_interval: DEFAULT_POLL_INTERVAL, max_iterations: nil, stop_when_idle: false)
      normalized_poll_interval = NonNegativeFiniteNumber.new(:poll_interval, poll_interval).normalize
      iteration_limit = IterationLimit.new(max_iterations)
      iterations = 0

      loop do
        result = work_once_result
        iterations += 1
        idle = result.equal?(NO_WORK_AVAILABLE)
        lease_lost = result.equal?(LEASE_LOST)
        iteration_limit_reached = iteration_limit.reached?(iterations)
        transient_result = idle || lease_lost

        return nil if stop_when_idle && idle
        return nil if iteration_limit_reached && transient_result
        return result if iteration_limit_reached

        runtime.sleep(normalized_poll_interval) if (idle || lease_lost) && normalized_poll_interval.positive?
      end
    end

    private

    attr_reader :configuration, :queue_store, :runtime

    def work_once_result
      reservation = reserve_next
      return NO_WORK_AVAILABLE unless reservation

      reservation_token = reservation.token
      running_job = start_execution_job(reservation_token)
      return LEASE_LOST if running_job.equal?(LEASE_LOST)

      begin
        handlers.fetch(running_job.handler).call(arguments: running_job.arguments)
      rescue StandardError
        return fail_execution_job(reservation_token)
      end

      complete_execution_job(reservation_token)
    end

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

    def complete_execution_job(reservation_token)
      queue_store.complete_execution(reservation_token:, now: current_time)
    rescue ExpiredReservationError, UnknownReservationError
      LEASE_LOST
    end

    def fail_execution_job(reservation_token)
      queue_store.fail_execution(reservation_token:, now: current_time)
    rescue ExpiredReservationError, UnknownReservationError
      LEASE_LOST
    end

    def start_execution_job(reservation_token)
      queue_store.start_execution(reservation_token:, now: current_time)
    rescue ExpiredReservationError, UnknownReservationError
      LEASE_LOST
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
        @handlers = HandlerRegistry.new(handlers)
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
        @sleeper = Callable.new(:sleeper, sleeper || ->(duration) { Kernel.sleep(duration) }).normalize
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
        raise InvalidWorkerConfigurationError, 'handlers must be a Hash' unless value.is_a?(Hash)

        @value = value
        @normalized_handlers = normalize
      end

      def normalize
        value.each_with_object({}) do |(name, handler), normalized|
          normalized_name = Identifier.new(:handler, name).normalize
          normalized[normalized_name] = HandlerExecution.build(handler:, handler_name: normalized_name)
        end.freeze
      end

      def fetch(handler_name)
        normalized_handlers.fetch(handler_name)
      rescue KeyError
        raise MissingHandlerError, "handler #{handler_name.inspect} is not registered"
      end

      private

      attr_reader :normalized_handlers, :value
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
        parameter_source = case handler
                           when Proc, Method, UnboundMethod
                             handler
                           else
                             handler.method(:call)
                           end
        @dispatcher = MethodDispatcher.new(parameters: parameter_source.parameters)
        @handler = handler
      end

      def call(arguments:)
        @dispatcher.call(arguments:) do |mode, payload|
          dispatch(mode, payload)
        end
      end

      private

      def dispatch(mode, payload)
        case mode
        when :none
          @handler.call
        when :positional_hash
          @handler.call(payload)
        else
          @handler.call(**payload)
        end
      end
    end

    # Executes handlers that respond to `perform`.
    class PerformExecution
      def initialize(handler)
        @dispatcher = MethodDispatcher.new(parameters: handler.method(:perform).parameters)
        @handler = handler
      end

      def call(arguments:)
        @dispatcher.call(arguments:) do |mode, payload|
          dispatch(mode, payload)
        end
      end

      private

      def dispatch(mode, payload)
        case mode
        when :none
          @handler.perform
        when :positional_hash
          @handler.perform(payload)
        else
          @handler.perform(**payload)
        end
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

    # Safely dispatches job arguments into supported Ruby method signatures.
    class MethodDispatcher
      KEYWORD_PARAMETER_TYPES = %i[key keyreq].freeze

      def initialize(parameters:)
        @parameters = parameters
      end

      def call(arguments:)
        if positional_hash_dispatch?
          yield(:positional_hash, arguments)
        elsif keyword_dispatch?
          yield(:keywords, keyword_arguments(arguments))
        elsif arguments.empty?
          yield(:none, nil)
        else
          raise InvalidWorkerConfigurationError, unsupported_signature_message
        end
      end

      private

      attr_reader :parameters

      def positional_hash_dispatch?
        parameters.length == 1 && %i[req opt].include?(parameters.first.fetch(0))
      end

      def any_parameter_matches?(*types)
        parameters.any? { |type, _name| types.include?(type) }
      end

      def keyword_dispatch?
        has_keyrest = any_parameter_matches?(:keyrest)
        return false if has_keyrest
        return false if any_parameter_matches?(:req, :opt, :rest)

        any_parameter_matches?(*KEYWORD_PARAMETER_TYPES)
      end

      def keyword_arguments(arguments)
        allowed_names = parameters.filter_map do |type, name|
          name if KEYWORD_PARAMETER_TYPES.include?(type)
        end
        unexpected_keys = arguments.keys - allowed_names.map(&:to_s)
        raise InvalidWorkerConfigurationError, unexpected_arguments_message(unexpected_keys) unless unexpected_keys.empty?

        allowed_names.each_with_object({}) do |name, normalized|
          key = name.to_s
          normalized[name] = arguments.fetch(key) if arguments.key?(key)
        end
      end

      def unsupported_signature_message
        'handler methods must accept no arguments, one Hash argument, or explicit keyword arguments without keyrest'
      end

      def unexpected_arguments_message(unexpected_keys)
        self.class.send(:unexpected_arguments_message, unexpected_keys)
      end

      def self.unexpected_arguments_message(unexpected_keys)
        "handler received unexpected argument keys: #{unexpected_keys.join(', ')}"
      end

      private_class_method :unexpected_arguments_message
    end

    private_constant :Callable,
                     :CallableExecution,
                     :Configuration,
                     :HandlerExecution,
                     :HandlerRegistry,
                     :Identifier,
                     :IterationLimit,
                     :LEASE_LOST,
                     :MethodDispatcher,
                     :NO_WORK_AVAILABLE,
                     :NonNegativeFiniteNumber,
                     :PerformExecution,
                     :PositiveFiniteNumber,
                     :QueueList,
                     :Runtime,
                     :UnsupportedExecution
  end
end
