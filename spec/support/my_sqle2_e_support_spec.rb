# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'mysql2'
require_relative 'mysql_e2e_support'

RSpec.describe MySQLE2ESupport do
  it 'treats ER_BAD_DB_ERROR as a missing database' do
    error = instance_double(Mysql2::Error, error_number: described_class::ER_BAD_DB_ERROR)

    expect(described_class.missing_database_error?(error)).to be(true)
  end

  it 'does not treat other MySQL errors as a missing database' do
    error = instance_double(Mysql2::Error, error_number: 2002)

    expect(described_class.missing_database_error?(error)).to be(false)
  end

  it 'prefers the admin database before the target database from the env url' do
    candidates = described_class.connection_params_candidates(
      'mysql2://root:secret@localhost:3306/karya',
      default_database_name: 'mysql'
    )

    expect(candidates.map { |params| params.fetch(:database) }).to eq(%w[mysql karya])
  end
end
