# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require 'uri'

module PostgresE2ESupport
  module_function

  DEFAULT_ADMIN_DATABASE_URL = 'postgres:///postgres'

  def admin_database_url
    ENV.fetch('PG_DATABASE_URL', DEFAULT_ADMIN_DATABASE_URL)
  end

  def current_rack_app
    Thread.current[:karya_current_rack_app]
  end

  def current_rack_app=(app)
    Thread.current[:karya_current_rack_app] = app
  end

  def with_postgres_database(prefix:)
    require 'pg'

    database_name = "#{prefix.tr('-', '_')}_#{SecureRandom.hex(6)}"
    admin_url = PostgresE2ESupport.admin_database_url
    connection = PG.connect(PostgresE2ESupport.admin_connection_params(admin_url))
    connection.exec("CREATE DATABASE #{PG::Connection.quote_ident(database_name)}")
    yield PostgresE2ESupport.database_url_for(admin_url, database_name)
  ensure
    connection&.exec("DROP DATABASE IF EXISTS #{PG::Connection.quote_ident(database_name)} WITH (FORCE)")
    connection&.close
  end

  def admin_connection_params(database_url)
    uri = URI.parse(database_url)
    database_name = uri.path.to_s.delete_prefix('/')
    {
      host: uri.host,
      port: uri.port,
      dbname: database_name.empty? ? 'postgres' : database_name,
      user: uri.user,
      password: uri.password
    }.compact
  end

  def database_url_for(admin_url, database_name)
    uri = URI.parse(admin_url)
    uri.path = "/#{database_name}"
    uri.to_s
  end
end

RSpec.configure do |config|
  config.include PostgresE2ESupport
end
