# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Hanami
    module CLI
      # Framework-native Hanami installer command.
      class Install < ::Hanami::CLI::Commands::App::Command
        desc 'Install Karya config, jobs, workflows, and backend migrations'

        option :backend, required: false, desc: 'postgres, mysql, or sqlite'

        def call(**options)
          backend = (options[:backend] || 'postgres').to_s
          migration_kind = Karya::Internal::FrameworkInstaller.migration_kind(backend)
          installer = Karya::Internal::FrameworkInstaller.sequel_migration_installer(migration_kind)
          root_path = Dir.pwd

          Karya::Internal::FrameworkInstaller.install!(
            framework_class_name: 'Karya::Hanami',
            root_path:,
            backend:,
            migration_kind:,
            migration_target_dir: File.join(root_path, 'db', 'migrations'),
            migration_installer: installer
          )
        end
      end
    end
  end
end
