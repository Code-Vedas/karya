# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'fileutils'

require_relative 'internal/mysql_schema_catalog'
require_relative 'internal/postgres_schema_catalog'

module Karya
  # Active Record migration/install support for SQL-backed Karya backends.
  module ActiveRecord
    module_function

    def install_postgres_migration(target_dir:, migration_name: 'Create Karya Postgres Backend')
      require_activerecord!

      class_name = normalize_migration_name(migration_name, fallback: 'CreateKaryaPostgresBackend')
      migration_version = "#{::ActiveRecord::VERSION::MAJOR}.#{::ActiveRecord::VERSION::MINOR}"
      file_name = "#{timestamp}_#{underscore(class_name)}.rb"
      path = File.expand_path(file_name, target_dir)

      FileUtils.mkdir_p(File.dirname(path))
      File.write(
        path,
        Karya::Internal::PostgresSchemaCatalog.render_active_record_migration(
          class_name:,
          migration_version:
        )
      )
      path
    end

    def install_mysql_migration(target_dir:, migration_name: 'Create Karya MySQL Backend')
      require_activerecord!

      class_name = normalize_migration_name(migration_name, fallback: 'CreateKaryaMysqlBackend')
      migration_version = "#{::ActiveRecord::VERSION::MAJOR}.#{::ActiveRecord::VERSION::MINOR}"
      file_name = "#{timestamp}_#{underscore(class_name)}.rb"
      path = File.expand_path(file_name, target_dir)

      FileUtils.mkdir_p(File.dirname(path))
      File.write(
        path,
        Karya::Internal::MySQLSchemaCatalog.render_active_record_migration(
          class_name:,
          migration_version:
        )
      )
      path
    end

    def require_activerecord!
      require 'active_record'
      require 'active_support/inflector'
    rescue LoadError => e
      raise LoadError,
            "#{e.message}. Add `gem 'activerecord'` to your Gemfile to use Karya::ActiveRecord SQL migration support.",
            cause: e
    end

    def normalize_migration_name(name, fallback: 'CreateKaryaPostgresBackend')
      normalized = name.to_s.each_char.with_object(+'') do |char, buffer|
        if alphanumeric?(char)
          buffer << char
        elsif !buffer.empty? && !buffer.end_with?(' ')
          buffer << ' '
        end
      end.split.map!(&:capitalize).join
      return normalized unless normalized.empty?

      fallback
    end

    def underscore(value)
      require_activerecord!
      ::ActiveSupport::Inflector.underscore(value)
    end

    def timestamp
      Time.now.utc.strftime('%Y%m%d%H%M%S')
    end

    def alphanumeric?(char)
      char.between?('a', 'z') ||
        char.between?('A', 'Z') ||
        char.between?('0', '9')
    end
  end
end
