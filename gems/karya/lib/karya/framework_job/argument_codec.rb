# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../worker/mutable_graph_copy'

module Karya
  module FrameworkJob
    # Serializes developer-authored framework job arguments into a Karya-owned envelope.
    module ArgumentCodec
      VERSION = 1
      VERSION_KEY = '__karya_framework_job_v'
      POSITIONAL_KEY = '__karya_framework_job_args'
      KEYWORD_KEY = '__karya_framework_job_kwargs'
      private_constant :VERSION, :VERSION_KEY, :POSITIONAL_KEY, :KEYWORD_KEY

      module_function

      def dump(args, kwargs)
        raise ArgumentError, 'args must be an Array' unless args.is_a?(Array)
        raise ArgumentError, 'kwargs must be a Hash' unless kwargs.is_a?(Hash)

        {
          VERSION_KEY => VERSION,
          POSITIONAL_KEY => mutable_graph_copy.call(args),
          KEYWORD_KEY => stringify_keys(kwargs)
        }.freeze
      end

      def load(arguments)
        raise InvalidWorkerConfigurationError, 'framework job arguments must be a Hash' unless arguments.is_a?(Hash)

        version = arguments.fetch(VERSION_KEY) do
          raise InvalidWorkerConfigurationError, 'framework job arguments are missing the version envelope'
        end
        raise InvalidWorkerConfigurationError, "unsupported framework job argument version #{version.inspect}" unless version == VERSION

        positional_arguments = arguments.fetch(POSITIONAL_KEY) do
          raise InvalidWorkerConfigurationError, 'framework job arguments are missing positional arguments'
        end
        keyword_arguments = arguments.fetch(KEYWORD_KEY) do
          raise InvalidWorkerConfigurationError, 'framework job arguments are missing keyword arguments'
        end

        raise InvalidWorkerConfigurationError, 'framework job positional arguments must be an Array' unless positional_arguments.is_a?(Array)
        raise InvalidWorkerConfigurationError, 'framework job keyword arguments must be a Hash' unless keyword_arguments.is_a?(Hash)

        [
          mutable_graph_copy.call(positional_arguments),
          mutable_graph_copy.call(keyword_arguments)
        ]
      end

      def framework_job_arguments?(arguments)
        arguments.is_a?(Hash) &&
          arguments.key?(VERSION_KEY) &&
          arguments.key?(POSITIONAL_KEY) &&
          arguments.key?(KEYWORD_KEY)
      end

      def stringify_keys(hash)
        hash.each_with_object({}) do |(key, value), normalized|
          normalized[key.to_s] = normalize_value(value)
        end.freeze
      end
      private_class_method :stringify_keys

      def normalize_value(value)
        case value
        when Hash
          stringify_keys(value)
        when Array
          value.map { |item| normalize_value(item) }
        else
          value
        end
      end
      private_class_method :normalize_value

      def mutable_graph_copy
        Karya::Worker.const_get(:MutableGraphCopy, false)
      end
      private_class_method :mutable_graph_copy
    end
  end
end
