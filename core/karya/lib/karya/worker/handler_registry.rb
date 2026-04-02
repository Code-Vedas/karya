# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Worker
    # Normalizes handler mappings into executable handler entries.
    class HandlerRegistry
      def initialize(value)
        raise InvalidWorkerConfigurationError, 'handlers must be a Hash' unless value.is_a?(Hash)

        @value = value
        @normalized_handlers = normalize
      end

      def normalize
        value.each_with_object({}) do |(name, handler), normalized|
          normalized_name = Primitives::Identifier.new(:handler, name, error_class: InvalidWorkerConfigurationError).normalize
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
  end
end
