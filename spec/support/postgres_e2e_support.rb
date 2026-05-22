# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require 'uri'

# Temporary Postgres database helpers for framework E2E coverage.
module PostgresE2ESupport
  module_function

  DEFAULT_ADMIN_DATABASE_URL = 'postgres:///postgres'
  UNDEFINED_DATABASE_SQLSTATE = '3D000'

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
    connection = PostgresE2ESupport.connect_admin(admin_url)
    connection.exec("CREATE DATABASE #{PG::Connection.quote_ident(database_name)}")
    yield PostgresE2ESupport.database_url_for(admin_url, database_name)
  ensure
    connection&.exec("DROP DATABASE IF EXISTS #{PG::Connection.quote_ident(database_name)} WITH (FORCE)")
    connection&.close
  end

  def connect_admin(database_url)
    connection_params_candidates(database_url, default_database_name: 'postgres').each do |params|
      return PG.connect(params)
    rescue PG::Error => e
      raise unless missing_database_error?(e)
    end

    raise PG::ConnectionBad, "Unable to connect to a Postgres admin database from #{database_url.inspect}"
  end

  def connection_params_candidates(database_url, default_database_name:)
    uri = URI.parse(database_url)
    database_name = uri.path.to_s.delete_prefix('/')
    candidate_database_names = [default_database_name, database_name].reject(&:empty?).uniq

    candidate_database_names.map do |candidate_database_name|
      {
        host: uri.host,
        port: uri.port,
        dbname: candidate_database_name,
        user: uri.user,
        password: uri.password
      }.compact
    end
  end

  def missing_database_error?(error)
    error.is_a?(PG::InvalidCatalogName) || pg_sqlstate(error) == UNDEFINED_DATABASE_SQLSTATE
  end

  def pg_sqlstate(error)
    result = error.result
    return nil unless result

    result.error_field(PG::Result::PG_DIAG_SQLSTATE)
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
