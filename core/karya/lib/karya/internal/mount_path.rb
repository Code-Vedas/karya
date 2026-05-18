# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Shared mount-path normalization for framework adapters.
    module MountPath
      module_function

      def build(default_mount_path, scope: nil)
        normalized_scope = normalize_scope(scope)
        return default_mount_path unless normalized_scope

        "/#{normalized_scope}#{default_mount_path}"
      end

      def normalize_scope(value)
        scope = trim_scope_delimiters(value.to_s.strip)
        return nil if scope.empty?

        scope
      end

      def trim_scope_delimiters(value)
        trimmed = value.dup
        trimmed = trimmed.delete_prefix('/') while trimmed.start_with?('/')
        trimmed = trimmed.delete_suffix('/') while trimmed.end_with?('/')
        trimmed
      end
      private_class_method :trim_scope_delimiters
    end
  end
end
