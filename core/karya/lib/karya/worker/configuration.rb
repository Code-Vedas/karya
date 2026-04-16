# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Worker
    # Validated worker bootstrap configuration.
    class Configuration
      OPTION_KEYS = %i[worker_id queues handlers lease_duration lifecycle retry_policy default_execution_timeout].freeze

      def self.from_options(options)
        attributes = OPTION_KEYS.each_with_object({}) do |key, collected|
          collected[key] = options.delete(key) if options.key?(key)
        end
        new(**attributes)
      end

      attr_reader :default_execution_timeout, :handlers, :lease_duration, :lifecycle, :queues, :retry_policy, :subscription, :worker_id

      def initialize(worker_id:, queues:, handlers:, lease_duration:, lifecycle: JobLifecycle.default_registry, retry_policy: nil,
                     default_execution_timeout: nil)
        @worker_id = Primitives::Identifier.new(:worker_id, worker_id, error_class: InvalidWorkerConfigurationError).normalize
        @handlers = handlers.is_a?(HandlerRegistry) ? handlers : HandlerRegistry.new(handlers)
        @subscription = Subscription.new(queues:, handler_names: @handlers.names)
        @queues = @subscription.queues
        @lease_duration = Primitives::PositiveFiniteNumber.new(:lease_duration, lease_duration, error_class: InvalidWorkerConfigurationError).normalize
        @lifecycle = Primitives::Lifecycle.new(:lifecycle, lifecycle, error_class: InvalidWorkerConfigurationError).normalize
        @retry_policy = Internal::RetryPolicyNormalizer.new(retry_policy, error_class: InvalidWorkerConfigurationError).normalize
        @default_execution_timeout = normalize_default_execution_timeout(default_execution_timeout)
      end

      private

      def normalize_default_execution_timeout(value)
        value&.then do
          Primitives::PositiveFiniteNumber.new(
            :default_execution_timeout,
            value,
            error_class: InvalidWorkerConfigurationError
          ).normalize
        end
      end
    end
  end
end
