# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'rake'

module Karya
  module Rails
    # Registers framework-native Karya rake tasks for Rails apps.
    module RakeTasks
      module_function

      def load!
        register_install_tasks
      end

      def register_install_tasks
        register_install_all_task
        register_install_migrations_task
      end

      def register_install_all_task
        ::Rake::Task.define_task('karya:install:all', [:backend] => :environment) do |_task, args|
          backend, migration_kind, installer = installer_configuration(args)
          Karya::Internal::FrameworkInstaller.install!(
            framework_class_name: 'Karya::Rails',
            root_path: ::Rails.root.to_s,
            backend:,
            migration_kind:,
            migration_target_dir: migration_target_dir,
            migration_installer: installer
          )
        end
      end

      def register_install_migrations_task
        ::Rake::Task.define_task('karya:install:migrations', [:backend] => :environment) do |_task, args|
          _backend, migration_kind, installer = installer_configuration(args)
          Karya::Internal::FrameworkInstaller.install_migrations!(
            migration_kind:,
            migration_target_dir:,
            migration_installer: installer
          )
        end
      end

      private_class_method :register_install_tasks, :register_install_all_task, :register_install_migrations_task

      def migration_target_dir
        ::Rails.root.join('db/migrate').to_s
      end

      def install_backend(args)
        (args[:backend] || ENV.fetch('KARYA_BACKEND', 'postgres')).to_s
      end

      def installer_configuration(args)
        backend = install_backend(args)
        migration_kind = Karya::Internal::FrameworkInstaller.migration_kind(backend)
        installer = Karya::Internal::FrameworkInstaller.active_record_migration_installer(migration_kind)
        [backend, migration_kind, installer]
      end

      private_class_method :migration_target_dir, :install_backend, :installer_configuration
    end
  end
end
