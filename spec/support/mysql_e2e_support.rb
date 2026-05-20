# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require 'uri'

module MySQLE2ESupport
  module_function

  DEFAULT_ADMIN_DATABASE_URL = 'mysql2://root:rootROOT!1@127.0.0.1:3306/mysql'

  def admin_database_url
    ENV.fetch('MYSQL_DATABASE_URL', DEFAULT_ADMIN_DATABASE_URL)
  end

  def with_mysql_database(prefix:)
    require 'mysql2'

    database_name = "#{prefix.tr('-', '_')}_#{SecureRandom.hex(6)}"
    admin_url = MySQLE2ESupport.admin_database_url
    connection = Mysql2::Client.new(**MySQLE2ESupport.admin_connection_params(admin_url))
    connection.query("CREATE DATABASE #{quote_ident(database_name)} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
    yield MySQLE2ESupport.database_url_for(admin_url, database_name)
  ensure
    connection&.query("DROP DATABASE IF EXISTS #{quote_ident(database_name)}")
    connection&.close
  end

  def admin_connection_params(database_url)
    uri = URI.parse(database_url)
    database_name = uri.path.to_s.delete_prefix('/')
    {
      host: uri.host || '127.0.0.1',
      port: uri.port || 3306,
      username: uri.user,
      password: uri.password,
      database: database_name.empty? ? 'mysql' : database_name,
      encoding: 'utf8mb4'
    }.compact
  end

  def database_url_for(admin_url, database_name)
    uri = URI.parse(admin_url)
    uri.path = "/#{database_name}"
    uri.to_s
  end

  def quote_ident(value)
    "`#{value.to_s.gsub('`', '``')}`"
  end
end

RSpec.configure do |config|
  config.include MySQLE2ESupport
end
