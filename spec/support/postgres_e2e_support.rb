# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# Postgres database helpers for framework E2E coverage.
module PostgresE2ESupport
  module_function

  DEFAULT_DATABASE_URL = 'postgres:///postgres'

  def database_url
    ENV.fetch('PG_DATABASE_URL', DEFAULT_DATABASE_URL)
  end

  def current_rack_app
    Thread.current[:karya_current_rack_app]
  end

  def current_rack_app=(app)
    Thread.current[:karya_current_rack_app] = app
  end

  def with_postgres_database(prefix:)
    _prefix = prefix
    yield PostgresE2ESupport.database_url
  end
end

RSpec.configure do |config|
  config.include PostgresE2ESupport
end
