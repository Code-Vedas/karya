# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Worker
    # Safely dispatches job arguments into supported Ruby method signatures.
    class MethodDispatcher
      KEYWORD_PARAMETER_TYPES = %i[key keyreq].freeze

      def initialize(parameters:)
        @parameters = parameters
      end

      def call(arguments:)
        if positional_hash_dispatch?
          yield(:positional_hash, MutableGraphCopy.call(arguments))
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
          normalized[name] = MutableGraphCopy.call(arguments.fetch(key)) if arguments.key?(key)
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
  end
end
