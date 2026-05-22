# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'pg'
require_relative 'postgres_e2e_support'

RSpec.describe PostgresE2ESupport do
  it 'treats InvalidCatalogName as a missing database' do
    error = PG::InvalidCatalogName.new('missing database')
    allow(error).to receive(:result).and_return(nil)

    expect(described_class.missing_database_error?(error)).to be(true)
  end

  it 'treats sqlstate 3D000 as a missing database' do
    result = instance_double(PG::Result, error_field: described_class::UNDEFINED_DATABASE_SQLSTATE)
    error = PG::ConnectionBad.new('missing database')
    allow(error).to receive(:result).and_return(result)

    expect(described_class.missing_database_error?(error)).to be(true)
  end

  it 'does not treat unrelated Postgres errors as a missing database' do
    result = instance_double(PG::Result, error_field: '08006')
    error = PG::ConnectionBad.new('connection failed')
    allow(error).to receive(:result).and_return(result)

    expect(described_class.missing_database_error?(error)).to be(false)
  end

  it 'prefers the admin database before the target database from the env url' do
    candidates = described_class.connection_params_candidates(
      'postgresql://user:secret@localhost:5432/karya',
      default_database_name: 'postgres'
    )

    expect(candidates.map { |params| params.fetch(:dbname) }).to eq(%w[postgres karya])
  end
end
