# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'fileutils'

module Karya
  module Internal
    # Shared logical worker naming and runtime state-file inference.
    module FrameworkRuntimeIdentity
      SAFE_PATH_COMPONENT_PATTERN = /\A[a-zA-Z0-9_-]+\z/

      module_function

      def parse_queues(value)
        queues = case value
                 when Array then value
                 else value.to_s.split(',')
                 end

        normalized = queues.map do |queue|
          normalize_path_component(:queue, queue)
        end

        raise ArgumentError, 'at least one queue is required' if normalized.empty?

        normalized
      end

      def worker_name(queues:, name: nil)
        return normalize_worker_name(name) if name

        parse_queues(queues).sort.join('-')
      end

      def worker_id(framework_name:, queues:, name: nil)
        "#{framework_name}-#{worker_name(queues:, name:)}"
      end

      def state_file(root_path:, queues:, name: nil)
        logical_name = worker_name(queues:, name:)
        File.join(root_path, 'tmp', 'karya', 'workers', "#{logical_name}.json")
      end

      def ensure_state_directory!(path)
        FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
        path
      end

      def normalize_worker_name(name)
        normalize_path_component(:worker_name, name)
      end
      private_class_method :normalize_worker_name

      def normalize_path_component(name, value)
        normalized = Primitives::Identifier.new(name, value, error_class: ArgumentError).normalize
        return normalized if SAFE_PATH_COMPONENT_PATTERN.match?(normalized)

        raise ArgumentError, "#{name} must contain only letters, numbers, hyphens, and underscores"
      end
      private_class_method :normalize_path_component
    end
  end
end
