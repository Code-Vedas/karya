# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'kaal'
require 'tmpdir'

module KaalSchemaSupport
  module_function

  def install_kaal_schema!(backend_name:, database_url:)
    require 'sequel'
    require 'sequel/extensions/migration'

    migration_templates = Kaal::Persistence::MigrationTemplates.for_backend(backend_name)
    return if migration_templates.empty?

    Dir.mktmpdir("kaal-schema-#{backend_name}-") do |migration_dir|
      migration_templates.each do |file_name, content|
        File.write(File.join(migration_dir, file_name), content)
      end

      database = Sequel.connect(sequel_database_url_for(database_url))
      run_sequel_migrations(
        database:,
        migration_dir:,
        table_name: "kaal_#{backend_name}",
        sentinel_table: :kaal_dispatches
      )
    ensure
      database&.disconnect
    end
  end

  def sequel_database_url_for(database_url)
    database_url.sub(/\Asqlite3:\/\//, 'sqlite://')
  end
end

RSpec.configure do |config|
  config.include KaalSchemaSupport
end
