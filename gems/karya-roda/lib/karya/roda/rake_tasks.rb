# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'json'
require 'rake'

module Karya
  module Roda
    # Registers framework-native Karya rake tasks for Roda apps.
    module RakeTasks
      module_function

      def load!
        return if loaded_for_current_application? || tasks_registered_for_current_application?

        register_work_task
        register_runtime_tasks
        register_install_tasks
        mark_loaded_for_current_application!
      end

      def register_work_task
        ::Rake::Task.define_task('karya:work', [:queues]) do |_task, args|
          Karya::Roda.load_config_file!
          Karya::Roda.support.run_worker(
            queues: normalized_queues(args),
            name: worker_name,
            **Karya::FrameworkJob::RuntimeOptions.from_env
          )
        end
      end

      def register_runtime_tasks
        register_runtime_task('inspect') { |queues| print_runtime_payload(Karya::Roda.runtime_inspect(queues:, name: worker_name)) }
        register_runtime_task('drain') { |queues| Karya::Roda.runtime_drain(queues:, name: worker_name) }
        register_runtime_task('force_stop') { |queues| Karya::Roda.runtime_force_stop(queues:, name: worker_name) }
      end

      def register_runtime_task(action, &)
        ::Rake::Task.define_task("karya:runtime:#{action}", [:queues]) do |_task, args|
          Karya::Roda.load_config_file!
          yield normalized_queues(args)
        end
      end

      def register_install_tasks
        register_install_all_task
        register_install_migrations_task
      end

      def register_install_all_task
        ::Rake::Task.define_task('karya:install:all', [:backend]) do |_task, args|
          backend, migration_kind, installer = installer_configuration(args)
          Karya::Internal::FrameworkInstaller.install!(
            framework_class_name: 'Karya::Roda',
            root_path: Dir.pwd,
            backend:,
            migration_kind:,
            migration_target_dir: migration_target_dir,
            migration_installer: installer
          )
        end
      end

      def register_install_migrations_task
        ::Rake::Task.define_task('karya:install:migrations', [:backend]) do |_task, args|
          _backend, migration_kind, installer = installer_configuration(args)
          Karya::Internal::FrameworkInstaller.install_migrations!(
            migration_kind:,
            migration_target_dir:,
            migration_installer: installer
          )
        end
      end

      def normalized_queues(args)
        Karya::Internal::FrameworkRuntimeIdentity.parse_queues(args[:queues] || ENV.fetch('KARYA_QUEUES', nil))
      end

      def worker_name
        ENV.fetch('KARYA_WORKER_NAME', nil)
      end

      def install_backend(args)
        (args[:backend] || ENV.fetch('KARYA_BACKEND', 'postgres')).to_s
      end

      def migration_target_dir
        File.join(Dir.pwd, 'db', 'migrate')
      end

      def print_runtime_payload(payload)
        puts JSON.pretty_generate(payload)
      end

      def installer_configuration(args)
        backend = install_backend(args)
        migration_kind = Karya::Internal::FrameworkInstaller.migration_kind(backend)
        installer = Karya::Internal::FrameworkInstaller.sequel_migration_installer(migration_kind)
        [backend, migration_kind, installer]
      end

      def loaded_for_current_application?
        loaded_applications.include?(current_application)
      end
      private_class_method :loaded_for_current_application?

      def mark_loaded_for_current_application!
        loaded_applications[current_application] = true
      end
      private_class_method :mark_loaded_for_current_application!

      def loaded_applications
        @loaded_applications ||= {}.compare_by_identity
      end
      private_class_method :loaded_applications

      def tasks_registered_for_current_application?
        ::Rake::Task.task_defined?('karya:work')
      end
      private_class_method :tasks_registered_for_current_application?

      def current_application
        ::Rake.application
      end
      private_class_method :register_install_all_task, :register_install_migrations_task, :current_application
    end
  end
end
