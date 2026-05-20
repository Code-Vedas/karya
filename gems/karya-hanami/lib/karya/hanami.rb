# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'karya'
require 'karya/dashboard'
require_relative 'hanami/version'

module Karya
  # The Karya::Hanami module serves as the main namespace for the Karya Hanami integration.
  module Hanami
    module_function

    DEFAULT_MOUNT_PATH = '/karya'

    def install_postgres_migration(target_dir:, migration_name: 'create_karya_postgres_backend')
      Karya::Sequel.install_postgres_migration(target_dir:, migration_name:)
    end

    def install_mysql_migration(target_dir:, migration_name: 'create_karya_mysql_backend')
      Karya::Sequel.install_mysql_migration(target_dir:, migration_name:)
    end

    def mount_path(prefix: nil)
      Karya::Internal::MountPath.build(DEFAULT_MOUNT_PATH, scope: prefix)
    end

    def render_dashboard_page(prefix: nil, title: Karya::Dashboard::DEFAULT_TITLE, asset_prefix: nil, name: 'dashboard')
      Karya::Dashboard.render_document(title:, mount_path: mount_path(prefix:), asset_prefix:, name:)
    end
  end
end
