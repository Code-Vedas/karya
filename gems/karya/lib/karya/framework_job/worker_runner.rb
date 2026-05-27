# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module FrameworkJob
    # Runs the existing worker supervisor with framework-discovered handlers.
    module WorkerRunner
      module_function

      def run(queues:, handlers:, **options)
        backend, queue_store = resolve_backend
        worker_configuration = {
          queue_store:,
          queues: normalize_queues(queues),
          handlers:
        }.merge(options)

        run_with_lifecycle(backend, queue_store) do
          Karya::WorkerSupervisor.new(**worker_configuration).run
        end
      end

      def resolve_backend
        return [nil, Karya.queue_store] unless Karya.backend_class

        backend = instantiate_backend
        [backend, build_queue_store(backend)]
      end
      module_function :resolve_backend

      def run_with_lifecycle(backend, queue_store)
        return yield unless backend

        backend.before_start(queue_store:)
        result = yield
        backend.after_stop(queue_store:)
        result
      rescue StandardError, SignalException, SystemExit
        safe_after_stop(backend, queue_store)
        raise
      end
      module_function :run_with_lifecycle

      def instantiate_backend
        backend_class = Karya.backend_class
        backend = backend_class.new(**Karya.backend_options)
        return backend if backend.is_a?(Karya::Backend::Base)

        raise Karya::InvalidBackendConfigurationError,
              "#{backend_class} must instantiate a backend including Karya::Backend::Base"
      rescue ArgumentError, TypeError => e
        raise Karya::InvalidBackendConfigurationError,
              "configured backend class #{backend_class} could not be initialized: #{e.message}"
      end
      module_function :instantiate_backend

      def build_queue_store(backend)
        queue_store = backend.build_queue_store
        return queue_store if queue_store.is_a?(Karya::QueueStore::Base)

        raise Karya::InvalidBackendConfigurationError,
              "#{backend.class} must build a Karya::QueueStore::Base"
      end
      module_function :build_queue_store

      def normalize_queues(queues)
        raise InvalidWorkerSupervisorConfigurationError, 'queues must be an Array' unless queues.is_a?(Array)

        queues.map do |queue|
          Primitives::Identifier.new(:queue, queue, error_class: InvalidWorkerSupervisorConfigurationError).normalize
        end
      end
      module_function :normalize_queues

      def safe_after_stop(backend, queue_store)
        return unless backend

        backend.after_stop(queue_store:)
      rescue StandardError
        nil
      end
      module_function :safe_after_stop
    end
  end
end
