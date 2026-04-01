# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Worker
    # Validated worker bootstrap configuration.
    class Configuration
      OPTION_KEYS = %i[worker_id queues handlers lease_duration lifecycle].freeze

      def self.from_options(options)
        attributes = OPTION_KEYS.each_with_object({}) do |key, collected|
          collected[key] = options.delete(key) if options.key?(key)
        end
        new(**attributes)
      end

      attr_reader :handlers, :lease_duration, :lifecycle, :queues, :worker_id

      def initialize(worker_id:, queues:, handlers:, lease_duration:, lifecycle: JobLifecycle.default_registry)
        @worker_id = Primitives::Identifier.new(:worker_id, worker_id, error_class: InvalidWorkerConfigurationError).normalize
        @queues = Primitives::QueueList.new(queues, error_class: InvalidWorkerConfigurationError).normalize
        @handlers = handlers.is_a?(HandlerRegistry) ? handlers : HandlerRegistry.new(handlers)
        @lease_duration = Primitives::PositiveFiniteNumber.new(:lease_duration, lease_duration, error_class: InvalidWorkerConfigurationError).normalize
        @lifecycle = Primitives::Lifecycle.new(:lifecycle, lifecycle, error_class: InvalidWorkerConfigurationError).normalize
      end
    end
  end
end
