# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'rails/generators'
require 'karya/rails'

module Karya
  module Generators
    # Installs framework-native Karya bootstrap files and migrations into a Rails app.
    class InstallGenerator < ::Rails::Generators::Base
      class_option :backend, type: :string, default: 'postgres', desc: 'Database backend: postgres, mysql, or sqlite'

      def install_karya
        backend = options.fetch('backend').to_s
        migration_kind = Karya::Internal::FrameworkInstaller.migration_kind(backend)
        installer = Karya::Internal::FrameworkInstaller.active_record_migration_installer(migration_kind)

        Karya::Internal::FrameworkInstaller.install!(
          framework_class_name: 'Karya::Rails',
          root_path: destination_root,
          backend:,
          migration_kind:,
          migration_target_dir: File.join(destination_root, 'db', 'migrate'),
          migration_installer: installer
        )
      end
    end
  end
end
