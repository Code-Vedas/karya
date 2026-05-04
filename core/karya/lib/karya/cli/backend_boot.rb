# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'English'

module Karya
  class CLI < Thor
    # Resolves configured backend classes into queue stores and manages backend lifecycle hooks.
    class BackendBoot
      class << self
        def resolve
          return [nil, Karya.queue_store] unless Karya.backend_class

          backend = instantiate
          [backend, build_queue_store(backend)]
        end

        def run_with_lifecycle(backend, queue_store, &)
          return yield unless backend

          execute_with_lifecycle(backend, queue_store, &)
        end

        private

        def instantiate
          backend_class = Karya.backend_class
          backend_class.new(**Karya.backend_options)
        rescue ArgumentError, TypeError => e
          raise Karya::InvalidBackendConfigurationError,
                "configured backend class #{backend_class} could not be initialized: #{e.message}"
        end

        def build_queue_store(backend)
          queue_store = backend.build_queue_store
          return queue_store if queue_store.is_a?(Karya::QueueStore::Base)

          raise Karya::InvalidBackendConfigurationError,
                "#{backend.class} must build a Karya::QueueStore::Base"
        end

        def execute_with_lifecycle(backend, queue_store)
          started = false
          suppress_cleanup_error = false
          result = nil

          begin
            backend.before_start(queue_store:)
            started = true
            result = yield
          rescue StandardError, SignalException, SystemExit
            suppress_cleanup_error = true
            raise
          ensure
            suppress_cleanup_error ||= $ERROR_INFO.is_a?(Exception)
            finish_lifecycle(backend, queue_store, started:, suppress_cleanup_error:, result:)
          end

          result
        end

        def finish_lifecycle(backend, queue_store, started:, suppress_cleanup_error:, result:)
          return unless started

          backend.after_stop(queue_store:)
        rescue StandardError
          raise unless suppress_cleanup_error || positive_status_result?(result)
        end

        def positive_status_result?(result)
          result.is_a?(Numeric) && result.positive?
        end
      end
    end
  end
end
