# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# Karya module serves as the namespace for all classes and modules related to the Karya gem.
module Karya
  # Internal implementation namespace. Constants here are not part of the supported public API.
  module Internal
  end

  # Error is the base class for all exceptions raised by Karya.
  class Error < StandardError; end

  # Raised when runtime code requires a configured queue store but none has been set.
  class MissingQueueStoreConfigurationError < Error; end

  class << self
    attr_reader :instrumenter

    def configure_instrumenter(instrumenter)
      @instrumenter = instrumenter
    end

    def configure_logger(logger)
      @logger = logger
    end

    def configure_queue_store(queue_store)
      @queue_store = queue_store
    end

    def logger
      return @logger if defined?(@logger) && @logger

      Internal::NullLogger.new
    end

    def queue_store
      return @queue_store if defined?(@queue_store) && @queue_store

      raise MissingQueueStoreConfigurationError, 'Karya.queue_store must be configured before starting a worker'
    end
  end
end
