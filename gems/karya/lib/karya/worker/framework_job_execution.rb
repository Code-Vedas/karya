# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Worker
    # Executes framework-authored Karya job classes by instantiating a fresh job object.
    class FrameworkJobExecution
      # Dispatches framework job arguments into `perform(*args, **kwargs)`.
      class PerformDispatcher
        KEYWORD_PARAMETER_TYPES = %i[key keyreq].freeze
        POSITIONAL_PARAMETER_TYPES = %i[req opt].freeze

        def initialize(parameters:)
          @parameters = parameters
        end

        def call(positional_arguments:, keyword_arguments:)
          validate_supported_signature
          validate_positional_arguments(positional_arguments)
          [MutableGraphCopy.call(positional_arguments), normalized_keyword_arguments(keyword_arguments)]
        end

        private

        attr_reader :parameters

        def validate_supported_signature
          return unless parameters.any? { |type, _name| type == :block }

          raise InvalidWorkerConfigurationError, 'framework job perform methods must not declare block parameters'
        end

        def validate_positional_arguments(positional_arguments)
          argument_count = positional_arguments.length
          positional_parameter_types = parameters.map(&:first)
          required_count = positional_parameter_types.count(:req)
          max_count = positional_rest? ? nil : positional_parameter_types.count { |type| POSITIONAL_PARAMETER_TYPES.include?(type) }

          if argument_count < required_count
            raise InvalidWorkerConfigurationError,
                  "framework job perform received too few positional arguments: expected at least #{required_count}, got #{argument_count}"
          end

          return if max_count.nil? || argument_count <= max_count

          raise InvalidWorkerConfigurationError,
                "framework job perform received too many positional arguments: expected at most #{max_count}, got #{argument_count}"
        end

        def normalized_keyword_arguments(keyword_arguments)
          raise InvalidWorkerConfigurationError, 'framework job keyword arguments must be a Hash' unless keyword_arguments.is_a?(Hash)

          return symbolize_keyword_arguments(keyword_arguments) if keyword_rest?

          allowed_names = keyword_parameter_names
          allowed_keys = allowed_names.map(&:to_s)
          unexpected_keys = keyword_arguments.keys - allowed_keys
          unless unexpected_keys.empty?
            raise InvalidWorkerConfigurationError, "framework job received unexpected keyword arguments: #{unexpected_keys.join(', ')}"
          end

          missing_required = required_keyword_parameter_names.reject { |name| keyword_arguments.key?(name.to_s) }
          unless missing_required.empty?
            raise InvalidWorkerConfigurationError, "framework job is missing required keyword arguments: #{missing_required.join(', ')}"
          end

          return {} if keyword_arguments.empty?

          allowed_names.each_with_object({}) do |name, normalized|
            key = name.to_s
            normalized[name] = MutableGraphCopy.call(keyword_arguments.fetch(key)) if keyword_arguments.key?(key)
          end
        end

        def symbolize_keyword_arguments(keyword_arguments)
          keyword_arguments.each_with_object({}) do |(key, value), normalized|
            normalized[key.to_sym] = MutableGraphCopy.call(value)
          end
        end

        def keyword_parameter_names
          parameters.filter_map { |type, name| name if KEYWORD_PARAMETER_TYPES.include?(type) }
        end

        def required_keyword_parameter_names
          parameters.filter_map { |type, name| name if type == :keyreq }
        end

        def positional_rest?
          parameters.any? { |type, _name| type == :rest }
        end

        def keyword_rest?
          parameters.any? { |type, _name| type == :keyrest }
        end
      end
      private_constant :PerformDispatcher

      def initialize(handler)
        @dispatcher = PerformDispatcher.new(parameters: handler.instance_method(:perform).parameters)
        @handler = handler
      end

      def call(arguments:)
        positional_arguments, keyword_arguments = FrameworkJob::ArgumentCodec.load(arguments)
        positional_arguments, keyword_arguments = @dispatcher.call(
          positional_arguments:,
          keyword_arguments:
        )
        @handler.new.perform(*positional_arguments, **keyword_arguments)
      end
    end
  end
end
