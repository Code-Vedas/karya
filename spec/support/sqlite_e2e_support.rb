# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'tmpdir'

module SQLiteE2ESupport
  module_function

  def with_sqlite_database(prefix:)
    Dir.mktmpdir("#{prefix.tr('_', '-')}-") do |directory|
      yield database_url_for(File.join(directory, 'karya.sqlite3'))
    end
  end

  def database_url_for(path)
    "sqlite3://#{File.expand_path(path)}"
  end

  def sequel_database_url_for(database_url)
    database_url.sub(/\Asqlite3:\/\//, 'sqlite://')
  end
end

RSpec.configure do |config|
  config.include SQLiteE2ESupport
end
