# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'fileutils'

require_relative 'internal/postgres_schema_catalog'

module Karya
  # Active Record migration/install support for the Postgres backend.
  module ActiveRecord
    module_function

    def install_postgres_migration(target_dir:, migration_name: 'Create Karya Postgres Backend')
      require_activerecord!

      class_name = normalize_migration_name(migration_name)
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

    def require_activerecord!
      require 'active_record'
    rescue LoadError => e
      raise LoadError,
            "#{e.message}. Add `gem 'activerecord'` to your Gemfile to use Karya::ActiveRecord Postgres migration support.",
            cause: e
    end

    def normalize_migration_name(name)
      normalized = name.to_s.gsub(/[^A-Za-z0-9]+/, ' ').split.map(&:capitalize).join
      return normalized unless normalized.empty?

      'CreateKaryaPostgresBackend'
    end

    def underscore(value)
      value
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .downcase
    end

    def timestamp
      Time.now.utc.strftime('%Y%m%d%H%M%S')
    end
  end
end
