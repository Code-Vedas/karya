# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'karya'
require 'karya/dashboard'
require_relative 'roda/version'
module Karya
  # Roda module used to integrate Karya to Roda applications.
  module Roda
    module_function

    DEFAULT_MOUNT_PATH = '/karya'

    def install_postgres_migration(target_dir:, migration_name: 'create_karya_postgres_backend')
      Karya::Sequel.install_postgres_migration(target_dir:, migration_name:)
    end

    def render_dashboard_page(scope: nil, title: Karya::Dashboard::DEFAULT_TITLE, asset_prefix: nil, name: 'dashboard')
      Karya::Dashboard.render_document(title:, mount_path: mount_path(scope:), asset_prefix:, name:)
    end

    def mount_path(scope: nil)
      normalized_scope = normalize_scope(scope)
      return DEFAULT_MOUNT_PATH unless normalized_scope

      "/#{normalized_scope}#{DEFAULT_MOUNT_PATH}"
    end

    def normalize_scope(value)
      scope = trim_scope_delimiters(value.to_s.strip)
      return nil if scope.empty?

      scope
    end
    private_class_method :normalize_scope

    def trim_scope_delimiters(value)
      trimmed = value.dup
      trimmed = trimmed.delete_prefix('/') while trimmed.start_with?('/')
      trimmed = trimmed.delete_suffix('/') while trimmed.end_with?('/')
      trimmed
    end
    private_class_method :trim_scope_delimiters
  end
end
