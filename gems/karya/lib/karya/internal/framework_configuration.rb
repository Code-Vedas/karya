# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Shared framework-facing configuration state.
    class FrameworkConfiguration
      DEFAULT_JOB_PATHS = ['app/jobs'].freeze
      DEFAULT_BOOT_FILES = [].freeze
      UNSET_BACKEND = Object.new.freeze

      def initialize
        @backend_class = nil
        @backend_options = nil
        @operator_authorizer = nil
        @outbound_event_dispatcher = nil
        @queue_store = nil
        @job_paths = DEFAULT_JOB_PATHS.dup
        @boot_files = DEFAULT_BOOT_FILES.dup
        @workflow_sources = []
      end

      attr_reader :backend_class, :backend_options, :boot_files, :job_paths,
                  :outbound_event_dispatcher, :queue_store, :workflow_sources
      attr_accessor :operator_authorizer

      def backend(backend_class = UNSET_BACKEND, **options)
        return @backend_class if backend_class.equal?(UNSET_BACKEND)

        Karya.configure_backend(backend_class, **options)
        @backend_class = backend_class
        @backend_options = options.dup.freeze
      end

      def queue_store=(queue_store)
        Karya.configure_queue_store(queue_store)
        @queue_store = queue_store
      end

      def outbound_event_dispatcher=(dispatcher)
        Karya.configure_outbound_event_dispatcher(dispatcher)
        @outbound_event_dispatcher = dispatcher
      end

      def job_paths=(paths)
        @job_paths = normalize_paths(:job_paths, paths)
      end

      def boot_files=(paths)
        @boot_files = normalize_paths(:boot_files, paths)
      end

      def register_workflows(*sources)
        normalized_sources = sources.flatten
        normalized_sources.each do |source|
          raise ArgumentError, 'workflow sources must respond to #karya_workflow_definitions' unless source.respond_to?(:karya_workflow_definitions)
        end

        @workflow_sources.concat(normalized_sources)
        @workflow_sources.uniq!
        @workflow_sources.freeze
      end

      private

      def normalize_paths(name, paths)
        raise ArgumentError, "#{name} must be an Array" unless paths.is_a?(Array)

        paths.map do |path|
          raise ArgumentError, "#{name} entries must be Strings" unless path.is_a?(String)

          path.strip
        end.reject(&:empty?)
      end
    end
  end
end
