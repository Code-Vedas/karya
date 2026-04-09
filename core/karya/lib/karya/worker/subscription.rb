# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Worker
    # Immutable worker subscription contract used by routing and reservation code.
    class Subscription
      attr_reader :handler_names, :queues

      def initialize(queues:, handler_names:)
        @queues = Primitives::QueueList.new(queues, error_class: InvalidWorkerConfigurationError).normalize
        @handler_names = normalize_handler_names(handler_names)
        freeze
      end

      def includes_queue?(queue)
        normalized_queue = Primitives::Identifier.new(:queue, queue, error_class: InvalidWorkerConfigurationError).normalize
        queues.include?(normalized_queue)
      end

      def handles?(handler_name)
        normalized_handler_name = Primitives::Identifier.new(
          :handler,
          handler_name,
          error_class: InvalidWorkerConfigurationError
        ).normalize
        handler_names.include?(normalized_handler_name)
      end

      def match?(job)
        includes_queue?(job.queue) && handles?(job.handler)
      end

      private

      def normalize_handler_names(value)
        normalized_names = Array(value).map do |handler_name|
          Primitives::Identifier.new(:handler, handler_name, error_class: InvalidWorkerConfigurationError).normalize
        end
        raise InvalidWorkerConfigurationError, 'handlers must be present' if normalized_names.empty?

        normalized_names.freeze
      end
    end
  end
end
