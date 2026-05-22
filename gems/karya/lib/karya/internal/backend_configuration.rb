# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Owns backend configuration validation and immutable option snapshotting.
    module BackendConfiguration
      module_function

      def configure(owner:, backend_class:, options:, load_backend_support:, synchronize_kaal_backend:)
        load_backend_support.call
        validated_backend_class = validate_backend_class(backend_class)
        validated_options = validate_backend_options(options)
        immutable_options = immutable_backend_option_value(validated_options)
        owner.instance_variable_set(:@backend_class, validated_backend_class)
        owner.instance_variable_set(:@backend_options, immutable_options)
        synchronize_kaal_backend.call(backend_class: validated_backend_class, backend_options: immutable_options)
        validated_backend_class
      end

      def backend_class(owner:, load_backend_support:)
        if owner.instance_variable_defined?(:@backend_class) && (configured_backend_class = owner.instance_variable_get(:@backend_class))
          load_backend_support.call
          return validate_backend_class(configured_backend_class)
        end

        nil
      end

      def backend_options(owner:, load_backend_support:)
        if owner.instance_variable_defined?(:@backend_options) && (configured_backend_options = owner.instance_variable_get(:@backend_options))
          load_backend_support.call
          validate_backend_options(configured_backend_options)
          return duplicate_backend_option_value(configured_backend_options)
        end

        {}
      end

      def generic_backend_option?(name, value)
        generic_callable_option?(name, value)
      end

      private_class_method def validate_backend_class(backend_class)
        raise InvalidBackendConfigurationError, 'configured backend class must be a Class' unless backend_class.is_a?(Class)
        raise InvalidBackendConfigurationError, 'configured backend class must include Karya::Backend::Base' unless backend_class <= Karya::Backend::Base

        backend_class
      end

      private_class_method def validate_backend_options(options)
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

      private_class_method def validate_backend_option(name, value)
        return if valid_backend_option_value?(name, value)

        raise InvalidBackendConfigurationError,
              "configured backend option #{name.inspect} has unsupported value #{value.class}"
      end

      private_class_method def valid_backend_option_value?(name, value)
        case value
        when NilClass, TrueClass, FalseClass, Numeric, String, Symbol,
          Class, QueueStore::Base, Backpressure::PolicySet, CircuitBreaker::PolicySet,
          Fairness::Policy
          true
        when Array
          valid_backend_option_array?(name, value)
        when Hash
          valid_backend_option_hash?(name, value)
        else
          generic_backend_option?(name, value)
        end
      end

      private_class_method def valid_backend_option_array?(name, value)
        value.all? { |item| valid_backend_option_value?(name, item) }
      end

      private_class_method def valid_backend_option_hash?(name, value)
        value.all? { |key, item| valid_backend_option_key?(key) && valid_backend_option_value?(name, item) }
      end

      private_class_method def valid_backend_option_key?(key)
        key.is_a?(Symbol) || key.is_a?(String)
      end

      private_class_method def validate_backend_option_key(key)
        return if key.is_a?(Symbol)

        raise InvalidBackendConfigurationError,
              "configured backend option keys must be Symbols: #{key.inspect}"
      end

      private_class_method def generic_callable_option?(name, value)
        Primitives::Callable.new(name, value, error_class: InvalidBackendConfigurationError).normalize
        true
      rescue InvalidBackendConfigurationError
        false
      end

      private_class_method def immutable_backend_option_value(value)
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

      private_class_method def duplicate_backend_option_value(value)
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

      private_class_method def immutable_backend_option_array(value)
        value.map { |item| immutable_backend_option_value(item) }.freeze
      end

      private_class_method def immutable_backend_option_hash(value)
        value.each_with_object({}) do |(key, item), snapshot|
          snapshot[immutable_backend_option_key(key)] = immutable_backend_option_value(item)
        end.freeze
      end

      private_class_method def duplicate_backend_option_array(value)
        value.map { |item| duplicate_backend_option_value(item) }
      end

      private_class_method def duplicate_backend_option_hash(value)
        value.each_with_object({}) do |(key, item), duplicated|
          duplicated[duplicate_backend_option_key(key)] = duplicate_backend_option_value(item)
        end
      end

      private_class_method def immutable_backend_option_key(key)
        return immutable_backend_option_string(key) if key.is_a?(String)

        key
      end

      private_class_method def duplicate_backend_option_key(key)
        return duplicate_backend_option_string(key) if key.is_a?(String)

        key
      end

      private_class_method def immutable_backend_option_string(value)
        return value if value.frozen?

        value.dup.freeze
      end

      private_class_method def duplicate_backend_option_string(value)
        value.dup
      end
    end
  end
end
