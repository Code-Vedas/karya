# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'karya'
require 'karya/dashboard'
require_relative 'sinatra/version'

module Karya
  # Namespace for the Karya Sinatra integration.
  module Sinatra
    module_function

    DEFAULT_MOUNT_PATH = '/karya'

    def install_postgres_migration(target_dir:, migration_name: 'create_karya_postgres_backend')
      Karya::Sequel.install_postgres_migration(target_dir:, migration_name:)
    end

    def render_dashboard_page(scope: nil, title: Karya::Dashboard::DEFAULT_TITLE, asset_prefix: nil, name: 'dashboard')
      Karya::Dashboard.render_document(title:, mount_path: mount_path(scope:), asset_prefix:, name:)
    end

    def mount_path(scope: nil)
      Karya::Internal::MountPath.build(DEFAULT_MOUNT_PATH, scope:)
    end
  end
end
