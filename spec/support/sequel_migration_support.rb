# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module SequelMigrationSupport
  module_function

  def run_sequel_migrations(database:, migration_dir:, table_name:, sentinel_table: nil)
    return if sentinel_table && database.table_exists?(sentinel_table)

    Sequel::Migrator.run(
      database,
      migration_dir,
      table: normalize_table_name(table_name),
      allow_missing_migration_files: true
    )
  end

  def normalize_table_name(value)
    "schema_migrations_#{value.to_s.gsub(/[^a-zA-Z0-9_]/, '_').downcase}"
  end
end

RSpec.configure do |config|
  config.include SequelMigrationSupport
end
