# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../internal/framework_job_registry'

module Karya
  module FrameworkJob
    # Loads framework job files and resolves discovered handlers.
    class Discovery
      DEFAULT_BOOT_FILES = [].freeze
      DEFAULT_JOB_PATHS = ['app/jobs'].freeze

      def initialize(root_path:, job_base:, job_paths: DEFAULT_JOB_PATHS, boot_files: DEFAULT_BOOT_FILES, extra_handlers: {}, eager_load: nil)
        @root_path = root_path
        @job_base = job_base
        @job_paths = normalize_relative_paths(job_paths, name: :job_paths)
        @boot_files = normalize_relative_paths(boot_files, name: :boot_files)
        @extra_handlers = normalize_extra_handlers(extra_handlers)
        @eager_load = eager_load
      end

      def handlers
        load_environment
        discovered_framework_handlers.merge(extra_handlers)
      end

      private

      attr_reader :boot_files, :eager_load, :extra_handlers, :job_base, :job_paths, :root_path

      def discovered_framework_handlers
        Internal::FrameworkJobRegistry.entries.each_with_object({}) do |entry, handlers|
          next unless entry.framework_job_class?(job_base)
          next unless defined_under_job_paths?(entry.source_path)

          klass = entry.klass
          handlers[klass.handler_name] = klass
        end
      end

      def load_environment
        Array(boot_files).each { |relative_path| require expanded_path(relative_path) }
        Array(job_paths).flat_map { |relative_path| job_files(relative_path) }.each { |job_file| require job_file }
        eager_load&.call
      end

      def expanded_path(relative_path)
        File.expand_path(relative_path, root_path)
      end

      def defined_under_job_paths?(source_path)
        return false unless source_path

        expanded_source_path = File.realpath(source_path)
        job_paths.any? do |relative_path|
          expanded_source_path.start_with?("#{File.realpath(expanded_path(relative_path))}/")
        end
      rescue Errno::ENOENT
        false
      end

      def job_files(relative_path)
        Dir.glob(File.join(expanded_path(relative_path), '**', '*.rb'))
      end

      def normalize_relative_paths(paths, name:)
        raise ArgumentError, "#{name} must be an Array" unless paths.is_a?(Array)

        paths.map do |path|
          raise ArgumentError, "#{name} entries must be Strings" unless path.is_a?(String)

          path.strip
        end.reject(&:empty?).freeze
      end

      def normalize_extra_handlers(handlers)
        raise ArgumentError, 'extra_handlers must be a Hash' unless handlers.is_a?(Hash)

        handlers.each_with_object({}) do |(name, handler), normalized|
          normalized_name = Primitives::Identifier.new(:handler, name, error_class: InvalidWorkerConfigurationError).normalize
          normalized[normalized_name] = handler
        end.freeze
      end
    end
  end
end
