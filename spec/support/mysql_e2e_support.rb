# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require 'uri'

# Temporary MySQL database helpers for framework E2E coverage.
module MySQLE2ESupport
  module_function

  DEFAULT_ADMIN_DATABASE_URL = 'mysql2://root:rootROOT!1@127.0.0.1:3306/mysql'
  ER_BAD_DB_ERROR = 1049

  def admin_database_url
    ENV.fetch('MYSQL_DATABASE_URL', DEFAULT_ADMIN_DATABASE_URL)
  end

  def with_mysql_database(prefix:)
    require 'mysql2'

    database_name = "#{prefix.tr('-', '_')}_#{SecureRandom.hex(6)}"
    admin_url = MySQLE2ESupport.admin_database_url
    connection = MySQLE2ESupport.connect_admin(admin_url)
    connection.query("CREATE DATABASE #{quote_ident(database_name)} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
    yield MySQLE2ESupport.database_url_for(admin_url, database_name)
  ensure
    connection&.query("DROP DATABASE IF EXISTS #{quote_ident(database_name)}")
    connection&.close
  end

  def connect_admin(database_url)
    connection_params_candidates(database_url, default_database_name: 'mysql').each do |params|
      return Mysql2::Client.new(**params)
    rescue Mysql2::Error => e
      raise unless missing_database_error?(e)
    end

    raise Mysql2::Error, "Unable to connect to a MySQL admin database from #{database_url.inspect}"
  end

  def connection_params_candidates(database_url, default_database_name:)
    uri = URI.parse(database_url)
    database_name = uri.path.to_s.delete_prefix('/')
    candidate_database_names = [default_database_name, database_name].reject(&:empty?).uniq

    candidate_database_names.map do |candidate_database_name|
      {
        host: uri.host || '127.0.0.1',
        port: uri.port || 3306,
        username: uri.user,
        password: uri.password,
        database: candidate_database_name,
        encoding: 'utf8mb4'
      }.compact
    end
  end

  def missing_database_error?(error)
    error.error_number == ER_BAD_DB_ERROR
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
