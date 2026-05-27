# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# MySQL database helpers for framework E2E coverage.
module MySQLE2ESupport
  module_function

  DEFAULT_DATABASE_URL = 'mysql2://root:rootROOT!1@127.0.0.1:3306/mysql'

  def database_url
    ENV.fetch('MYSQL_DATABASE_URL', DEFAULT_DATABASE_URL)
  end

  def with_mysql_database(prefix:)
    _prefix = prefix
    yield MySQLE2ESupport.database_url
  end
end

RSpec.configure do |config|
  config.include MySQLE2ESupport
end
