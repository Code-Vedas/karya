# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'internal/null_logger'
require_relative 'internal/backend_configuration'
require_relative 'primitives/callable'
require 'securerandom'

# Karya module serves as the namespace for all classes and modules related to the Karya gem.
module Karya
  # Internal implementation namespace. Constants here are not part of the supported public API.
  module Internal
  end

  # Error is the base class for all exceptions raised by Karya.
  class Error < StandardError; end

  # Raised when runtime code requires a configured queue store but none has been set.
  class MissingQueueStoreConfigurationError < Error; end

  # Raised when framework-facing file configuration is invalid.
  class InvalidFrameworkConfigurationError < Error; end

  # Raised when a caller asks for scheduled enqueue that is not currently supported.
  class UnsupportedSchedulingError < Error; end

  # Raised when outbound event input cannot be normalized into a supported contract.
  class InvalidOutboundEventError < Error; end

  # Raised when a caller asks for an outbound event that is not part of the supported contract.
  class UnsupportedOutboundEventError < Error; end

  # Raised when a webhook signature cannot be parsed or verified.
  class InvalidWebhookSignatureError < Error; end

  class << self
    attr_reader :instrumenter, :outbound_event_dispatcher, :operator_authorizer

    def configure_instrumenter(instrumenter)
      # Process-wide default used when a runtime does not receive an explicit instrumenter.
      @instrumenter = instrumenter
    end

    def configure_outbound_event_dispatcher(outbound_event_dispatcher)
      # Process-wide default used when a runtime does not receive an explicit outbound event dispatcher.
      @outbound_event_dispatcher = outbound_event_dispatcher
    end

    def configure_logger(logger)
      # Process-wide default used when a runtime does not receive an explicit logger.
      @logger = logger
    end

    def configure_queue_store(queue_store)
      @queue_store = queue_store
    end

    def configure_operator_authorizer(authorizer)
      authorizer&.public_method(:call)
      @operator_authorizer = authorizer
    rescue NameError
      raise ArgumentError, 'operator authorizer must respond to #call'
    end

    def configure_backend(backend_class, **options)
      Internal::BackendConfiguration.configure(
        owner: self,
        backend_class:,
        options:,
        load_backend_support: method(:load_backend_support),
        synchronize_kaal_backend: method(:synchronize_kaal_backend)
      )
    end

    def logger
      return @logger if defined?(@logger) && @logger

      Internal::NullLogger.new
    end

    def backend_class
      Internal::BackendConfiguration.backend_class(
        owner: self,
        load_backend_support: method(:load_backend_support)
      )
    end

    def backend_options
      Internal::BackendConfiguration.backend_options(
        owner: self,
        load_backend_support: method(:load_backend_support)
      )
    end

    def queue_store
      return @queue_store if defined?(@queue_store) && @queue_store

      raise MissingQueueStoreConfigurationError, 'Karya.queue_store must be configured before starting a worker'
    end

    def enqueue(
      queue:,
      handler:,
      arguments: {},
      now: Time.now.utc,
      job_id: SecureRandom.uuid,
      created_at: now,
      enqueued_at: now
    )
      normalized_now = normalize_enqueue_time(now)
      normalized_created_at = normalize_enqueue_time(created_at)
      normalized_enqueued_at = normalize_enqueue_time(enqueued_at)
      job = Job.new(
        id: job_id,
        queue:,
        handler:,
        arguments:,
        state: :submission,
        created_at: normalized_created_at,
        enqueued_at: normalized_enqueued_at
      )
      _resolve_queue_store.enqueue(job:, now: normalized_now)
      job
    end

    def enqueue_at(
      queue:,
      handler:,
      at:, arguments: {},
      now: Time.now.utc,
      job_id: SecureRandom.uuid
    )
      normalized_now = normalize_enqueue_time(now)
      normalized_scheduled_at = normalize_scheduled_time(at)
      return enqueue(queue:, handler:, arguments:, now: normalized_now, job_id:) if normalized_scheduled_at <= normalized_now

      schedule_with_kaal(
        queue:,
        handler:,
        arguments:,
        job_id:,
        created_at: normalized_now,
        scheduled_at: normalized_scheduled_at
      )
    end

    def _resolve_queue_store
      resolve_queue_store
    end

    private

    def schedule_with_kaal(queue:, handler:, arguments:, job_id:, created_at:, scheduled_at:)
      require_relative 'internal/kaal_delayed_scheduler'
      Internal::KaalDelayedScheduler.schedule(
        queue:,
        handler:,
        arguments:,
        job_id:,
        created_at:,
        scheduled_at:
      )
    end

    def load_backend_support
      require_relative 'backend'
      require_relative 'job'
      require_relative 'queue_store/base'
      require_relative 'backpressure'
      require_relative 'circuit_breaker'
      require_relative 'fairness'
      require_relative 'framework_runtime'
      require_relative 'internal/kaal_backend_mapper'
    end

    def resolve_queue_store
      configured_queue_store = @queue_store if defined?(@queue_store)
      return configured_queue_store if configured_queue_store

      current_runtime = FrameworkRuntime.current_runtime
      return current_runtime.queue_store if current_runtime

      configured_backend_class = backend_class
      raise MissingQueueStoreConfigurationError, 'Karya backend must be configured before enqueuing jobs' unless configured_backend_class

      FrameworkRuntime.shared_runtime(backend_class: configured_backend_class, backend_options: backend_options).queue_store
    end

    def synchronize_kaal_backend(backend_class:, backend_options:)
      Internal::KaalBackendMapper.synchronize!(backend_class:, backend_options:)
    rescue LoadError
      nil
    end

    def normalize_enqueue_time(value)
      case value
      when Time
        value.utc
      else
        Time.at(value.to_f).utc
      end
    end

    def normalize_scheduled_time(timestamp)
      normalize_enqueue_time(timestamp)
    end

    def generic_backend_option?(name, value)
      Internal::BackendConfiguration.generic_backend_option?(name, value)
    end
  end
end
