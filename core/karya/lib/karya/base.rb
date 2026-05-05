# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'internal/null_logger'
require_relative 'primitives/callable'

# Karya module serves as the namespace for all classes and modules related to the Karya gem.
module Karya
  # Internal implementation namespace. Constants here are not part of the supported public API.
  module Internal
  end

  # Error is the base class for all exceptions raised by Karya.
  class Error < StandardError; end

  # Raised when runtime code requires a configured queue store but none has been set.
  class MissingQueueStoreConfigurationError < Error; end

  # Raised when outbound event input cannot be normalized into a supported contract.
  class InvalidOutboundEventError < Error; end

  # Raised when a caller asks for an outbound event that is not part of the supported contract.
  class UnsupportedOutboundEventError < Error; end

  # Raised when a webhook signature cannot be parsed or verified.
  class InvalidWebhookSignatureError < Error; end

  class << self
    attr_reader :instrumenter, :outbound_event_dispatcher

    def configure_instrumenter(instrumenter)
      # Process-wide default used when a runtime does not receive an explicit instrumenter.
      @instrumenter = instrumenter
    end

    def configure_outbound_event_dispatcher(outbound_event_dispatcher)
      # Process-wide default used when a runtime does not receive an explicit outbound event dispatcher.
      @outbound_event_dispatcher = outbound_event_dispatcher
    end

    def configure_logger(logger)
      # Process-wide default used when a runtime does not receive an explicit logger.
      @logger = logger
    end

    def configure_queue_store(queue_store)
      @queue_store = queue_store
    end

    def configure_backend(backend_class, **options)
      load_backend_support
      validate_backend_class(backend_class)
      validate_backend_options(options)
      @backend_class = backend_class
      @backend_options = immutable_backend_option_value(options)
      @backend_class
    end

    def logger
      return @logger if defined?(@logger) && @logger

      Internal::NullLogger.new
    end

    def backend_class
      if defined?(@backend_class) && @backend_class
        load_backend_support
        return validate_backend_class(@backend_class)
      end

      nil
    end

    def backend_options
      if defined?(@backend_options) && @backend_options
        load_backend_support
        validate_backend_options(@backend_options)
        return duplicate_backend_option_value(@backend_options)
      end

      {}
    end

    def queue_store
      return @queue_store if defined?(@queue_store) && @queue_store

      raise MissingQueueStoreConfigurationError, 'Karya.queue_store must be configured before starting a worker'
    end

    private

    def load_backend_support
      require_relative 'backend'
      require_relative 'queue_store/base'
      require_relative 'backpressure'
      require_relative 'circuit_breaker'
      require_relative 'fairness'
    end

    def validate_backend_class(backend_class)
      raise InvalidBackendConfigurationError, 'configured backend class must be a Class' unless backend_class.is_a?(Class)
      raise InvalidBackendConfigurationError, 'configured backend class must include Karya::Backend::Base' unless backend_class <= Karya::Backend::Base
      unless default_backend_constructor?(backend_class)
        raise InvalidBackendConfigurationError,
              'configured backend class must use the default .new constructor'
      end

      backend_class
    end

    def validate_backend_options(options)
      unless options.is_a?(Hash)
        raise InvalidBackendConfigurationError,
              "configured backend options must be a Hash: #{options.class}"
      end

      options.each do |name, value|
        validate_backend_option_key(name)
        validate_backend_option(name, value)
      end

      options
    end

    def validate_backend_option(name, value)
      return if valid_backend_option_value?(name, value)

      raise InvalidBackendConfigurationError,
            "configured backend option #{name.inspect} has unsupported value #{value.class}"
    end

    def valid_backend_option_value?(name, value)
      case value
      when NilClass, TrueClass, FalseClass, Numeric, String, Symbol,
        QueueStore::Base, Backpressure::PolicySet, CircuitBreaker::PolicySet,
        Fairness::Policy, Class
        true
      when Array
        valid_backend_option_array?(name, value)
      when Hash
        valid_backend_option_hash?(name, value)
      else
        queue_store_factory_option?(name, value) || generic_backend_option?(name, value)
      end
    end

    def valid_backend_option_array?(name, value)
      value.all? { |item| valid_backend_option_value?(name, item) }
    end

    def valid_backend_option_hash?(name, value)
      value.all? { |key, item| valid_backend_option_key?(key) && valid_backend_option_value?(name, item) }
    end

    def valid_backend_option_key?(key)
      key.is_a?(Symbol) || key.is_a?(String)
    end

    def validate_backend_option_key(key)
      return if key.is_a?(Symbol)

      raise InvalidBackendConfigurationError,
            "configured backend option keys must be Symbols: #{key.inspect}"
    end

    def queue_store_factory_option?(name, value)
      return false unless name == :queue_store_class

      if value.is_a?(Class)
        valid_queue_store_factory_class?(value)
      else
        valid_queue_store_factory_object?(value)
      end
    end

    def valid_queue_store_factory_class?(value)
      value < QueueStore::Base
    rescue NameError
      false
    end

    def valid_queue_store_factory_object?(value)
      value.singleton_class.public_method_defined?(:new)
    end

    def default_backend_constructor?(backend_class)
      backend_class.method(:new).owner == Class
    end

    def generic_callable_option?(name, value)
      Primitives::Callable.new(name, value, error_class: InvalidBackendConfigurationError).normalize
      true
    rescue InvalidBackendConfigurationError
      false
    end

    def generic_backend_option?(name, value)
      return false if name == :queue_store_class

      generic_callable_option?(name, value)
    end

    def immutable_backend_option_value(value)
      case value
      when Array
        immutable_backend_option_array(value)
      when Hash
        immutable_backend_option_hash(value)
      when String
        immutable_backend_option_string(value)
      else
        value
      end
    end

    def duplicate_backend_option_value(value)
      case value
      when Array
        duplicate_backend_option_array(value)
      when Hash
        duplicate_backend_option_hash(value)
      when String
        duplicate_backend_option_string(value)
      else
        value
      end
    end

    def immutable_backend_option_array(value)
      value.map { |item| immutable_backend_option_value(item) }.freeze
    end

    def immutable_backend_option_hash(value)
      value.each_with_object({}) do |(key, item), snapshot|
        snapshot[immutable_backend_option_key(key)] = immutable_backend_option_value(item)
      end.freeze
    end

    def duplicate_backend_option_array(value)
      value.map { |item| duplicate_backend_option_value(item) }
    end

    def duplicate_backend_option_hash(value)
      value.each_with_object({}) do |(key, item), duplicated|
        duplicated[duplicate_backend_option_key(key)] = duplicate_backend_option_value(item)
      end
    end

    def immutable_backend_option_key(key)
      return immutable_backend_option_string(key) if key.is_a?(String)

      key
    end

    def duplicate_backend_option_key(key)
      return duplicate_backend_option_string(key) if key.is_a?(String)

      key
    end

    def immutable_backend_option_string(value)
      return value if value.frozen?

      value.dup.freeze
    end

    def duplicate_backend_option_string(value)
      value.dup
    end
  end
end
