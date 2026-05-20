# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'rails'
require 'action_controller/railtie'
require 'karya'
require 'karya/dashboard'

require_relative 'rails/version'
require_relative 'rails/engine'

module Karya
  # Karya::Rails module serves as the main namespace for all Rails-specific integrations and functionalities related to the Karya gem.
  module Rails
    module_function

    DEFAULT_MOUNT_PATH = '/karya'

    def install_postgres_migration(target_dir:, migration_name: 'Create Karya Postgres Backend')
      Karya::ActiveRecord.install_postgres_migration(target_dir:, migration_name:)
    end

    def install_mysql_migration(target_dir:, migration_name: 'Create Karya MySQL Backend')
      Karya::ActiveRecord.install_mysql_migration(target_dir:, migration_name:)
    end

    def install_sqlite_migration(target_dir:, migration_name: 'Create Karya SQLite Backend')
      Karya::ActiveRecord.install_sqlite_migration(target_dir:, migration_name:)
    end

    def render_dashboard_page(
      scope: nil,
      mount_path: DEFAULT_MOUNT_PATH,
      title: Karya::Dashboard::DEFAULT_TITLE,
      asset_prefix: nil,
      name: 'dashboard'
    )
      if scope
        raise ArgumentError, 'scope and mount_path cannot be combined' unless mount_path == DEFAULT_MOUNT_PATH

        mount_path = Karya::Internal::MountPath.build(DEFAULT_MOUNT_PATH, scope:)
      end
      Karya::Dashboard.render_document(title:, mount_path:, asset_prefix:, name:)
    end
  end
end
