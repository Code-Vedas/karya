# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class WorkerSupervisor
    # Normalizes handler mappings into a string-keyed frozen Hash.
    class HandlerMapping
      def initialize(value)
        @value = value
      end

      def normalize
        raise InvalidWorkerSupervisorConfigurationError, 'handlers must be a Hash' unless value.is_a?(Hash)
        raise InvalidWorkerSupervisorConfigurationError, 'handlers must be present' if value.empty?

        value.each_with_object({}) do |(name, handler), normalized|
          normalized_name = Primitives::Identifier.new(:handler, name, error_class: InvalidWorkerSupervisorConfigurationError).normalize
          raise InvalidWorkerSupervisorConfigurationError, "handlers must be unique: #{normalized_name}" if normalized.key?(normalized_name)

          normalized[normalized_name] = handler
        end.freeze
      end

      private

      attr_reader :value
    end
  end
end
