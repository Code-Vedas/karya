# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'internal/null_logger'

# Karya module serves as the namespace for all classes and modules related to the Karya gem.
module Karya
  # Internal implementation namespace. Constants here are not part of the supported public API.
  module Internal
  end

  # Error is the base class for all exceptions raised by Karya.
  class Error < StandardError; end

  # Raised when runtime code requires a configured queue store but none has been set.
  class MissingQueueStoreConfigurationError < Error; end

  # Raised when outbound event input cannot be normalized into a supported contract.
  class InvalidOutboundEventError < Error; end

  # Raised when a caller asks for an outbound event that is not part of the supported contract.
  class UnsupportedOutboundEventError < Error; end

  # Raised when a webhook signature cannot be parsed or verified.
  class InvalidWebhookSignatureError < Error; end

  class << self
    attr_reader :instrumenter, :outbound_event_dispatcher

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

    def configure_backend(backend_class, **options)
      @backend_class = backend_class
      @backend_options = options.dup.freeze
      @backend_class
    end

    def logger
      return @logger if defined?(@logger) && @logger

      Internal::NullLogger.new
    end

    def backend_class
      return @backend_class if defined?(@backend_class) && @backend_class

      nil
    end

    def backend_options
      return @backend_options.dup if defined?(@backend_options) && @backend_options

      {}
    end

    def queue_store
      return @queue_store if defined?(@queue_store) && @queue_store

      raise MissingQueueStoreConfigurationError, 'Karya.queue_store must be configured before starting a worker'
    end
  end
end
