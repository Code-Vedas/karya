# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'fileutils'

module Karya
  module Internal
    # Shared installer for framework-native Karya bootstrap files and migrations.
    module FrameworkInstaller
      module_function

      def install!(framework_class_name:, root_path:, backend:, migration_kind:, migration_target_dir:, migration_installer:)
        create_runtime_config(root_path:, backend:)
        create_application_job(root_path:, framework_class_name:)
        create_workflow_source(root_path:, framework_class_name:)
        install_migrations!(
          migration_kind:,
          migration_target_dir:,
          migration_installer:
        )
      end

      def migration_kind(backend)
        kind = backend.to_s.to_sym
        default_migration_name(kind)
        kind
      rescue KeyError
        raise ArgumentError, "unsupported backend #{backend.inspect}"
      end

      def install_migrations!(migration_kind:, migration_target_dir:, migration_installer:)
        migration_installer.call(
          target_dir: migration_target_dir,
          migration_name: default_migration_name(migration_kind)
        )
      end

      def active_record_migration_installer(migration_kind)
        {
          postgres: ->(**options) { Karya::ActiveRecord.install_postgres_migration(**options) },
          mysql: ->(**options) { Karya::ActiveRecord.install_mysql_migration(**options) },
          sqlite: ->(**options) { Karya::ActiveRecord.install_sqlite_migration(**options) }
        }.fetch(migration_kind)
      end

      def sequel_migration_installer(migration_kind)
        {
          postgres: ->(**options) { Karya::Sequel.install_postgres_migration(**options) },
          mysql: ->(**options) { Karya::Sequel.install_mysql_migration(**options) },
          sqlite: ->(**options) { Karya::Sequel.install_sqlite_migration(**options) }
        }.fetch(migration_kind)
      end

      def create_runtime_config(root_path:, backend:)
        write_file(
          File.join(root_path, 'config', 'karya.yml'),
          <<~YAML
            defaults:
              backend: #{backend_name(backend)}
              backend_config:
                url: <%= ENV.fetch("DATABASE_URL") %>
              job_paths:
                - app/jobs
              boot_files: []

            development: {}
            test: {}
            production: {}
          YAML
        )
      end

      def create_initializer(root_path:, backend:, _framework_class_name: nil)
        create_runtime_config(root_path:, backend:)
      end
      module_function :create_initializer

      def create_application_job(root_path:, framework_class_name:)
        write_file(
          File.join(root_path, 'app', 'jobs', 'application_job.rb'),
          <<~RUBY
            # frozen_string_literal: true

            class ApplicationJob < #{framework_class_name}::Job
              abstract!
            end
          RUBY
        )
      end

      def create_workflow_source(root_path:, framework_class_name:)
        write_file(
          File.join(root_path, 'app', 'workflows', 'application_workflows.rb'),
          <<~RUBY
            # frozen_string_literal: true

            module ApplicationWorkflows
              extend #{framework_class_name}::Workflow::Source
            end
          RUBY
        )
      end

      def write_file(path, content)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content) unless File.exist?(path)
      end
      module_function :write_file

      def backend_name(backend)
        {
          'postgres' => 'postgres',
          'mysql' => 'mysql',
          'sqlite' => 'sqlite'
        }.fetch(backend.to_s) { raise ArgumentError, "unsupported backend #{backend.inspect}" }
      end
      module_function :backend_name

      def backend_class_name(backend)
        {
          'postgres' => 'Postgres',
          'mysql' => 'MySQL',
          'sqlite' => 'SQLite'
        }.fetch(backend_name(backend))
      end
      module_function :backend_class_name

      def default_migration_name(migration_kind)
        {
          postgres: 'create_karya_postgres_backend',
          mysql: 'create_karya_mysql_backend',
          sqlite: 'create_karya_sqlite_backend'
        }.fetch(migration_kind)
      end
    end
  end
end
