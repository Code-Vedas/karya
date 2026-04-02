# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class WorkerSupervisor
    # Validated supervisor bootstrap configuration.
    class Configuration
      OPTION_KEYS = %i[
        handlers
        lease_duration
        lifecycle
        max_iterations
        poll_interval
        processes
        queues
        stop_when_idle
        threads
        worker_id
      ].freeze

      def self.from_options(options)
        attributes = OPTION_KEYS.each_with_object({}) do |key, collected|
          collected[key] = options.delete(key) if options.key?(key)
        end
        new(attributes)
      end

      def self.normalize_poll_interval(value)
        Primitives::NonNegativeFiniteNumber.new(
          :poll_interval,
          value,
          error_class: InvalidWorkerSupervisorConfigurationError
        ).normalize
      end

      def self.normalize_positive_integer(name, value)
        Primitives::PositiveInteger.new(name, value, error_class: InvalidWorkerSupervisorConfigurationError).normalize
      end

      attr_reader :handlers, :lease_duration, :max_iterations,
                  :lifecycle, :poll_interval, :processes, :queues, :stop_when_idle, :threads, :worker_id

      def initialize(attributes)
        assign_attributes(attributes)
      end

      def bounded_run?
        stop_when_idle || max_iterations != :unlimited
      end

      def validate_stop_when_idle
        return if [true, false].include?(stop_when_idle)

        raise InvalidWorkerSupervisorConfigurationError, 'stop_when_idle must be a boolean'
      end

      def assign_attributes(attributes)
        required_values = required_values_from(attributes)
        assign_required_attributes(required_values)
        assign_optional_attributes(attributes)
        validate_stop_when_idle
      end

      def required_values_from(attributes)
        %i[worker_id queues handlers lease_duration].to_h do |key|
          [
            key,
            attributes.fetch(key) do
              raise InvalidWorkerSupervisorConfigurationError, "#{key} is required"
            end
          ]
        end
      end

      def assign_required_attributes(required_values)
        @worker_id = Primitives::Identifier.new(:worker_id, required_values.fetch(:worker_id),
                                                error_class: InvalidWorkerSupervisorConfigurationError).normalize
        @queues = Primitives::QueueList.new(required_values.fetch(:queues),
                                            error_class: InvalidWorkerSupervisorConfigurationError).normalize
        @handlers = HandlerMapping.new(required_values.fetch(:handlers)).normalize
        @lease_duration = Primitives::PositiveFiniteNumber.new(
          :lease_duration,
          required_values.fetch(:lease_duration),
          error_class: InvalidWorkerSupervisorConfigurationError
        ).normalize
      end

      def assign_optional_attributes(attributes)
        configuration_class = self.class
        @lifecycle = Primitives::Lifecycle.new(
          :lifecycle,
          attributes.fetch(:lifecycle, JobLifecycle.default_registry),
          error_class: InvalidWorkerSupervisorConfigurationError
        ).normalize
        @poll_interval = configuration_class.normalize_poll_interval(attributes.fetch(:poll_interval, Worker::DEFAULT_POLL_INTERVAL))
        @max_iterations = MaxIterationsSetting.new(attributes.fetch(:max_iterations, :unlimited)).normalize
        @stop_when_idle = attributes.fetch(:stop_when_idle, false)
        @processes = configuration_class.normalize_positive_integer(:processes, attributes.fetch(:processes, DEFAULT_PROCESSES))
        @threads = configuration_class.normalize_positive_integer(:threads, attributes.fetch(:threads, DEFAULT_THREADS))
      end
    end
  end
end
