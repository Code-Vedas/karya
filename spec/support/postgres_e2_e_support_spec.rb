# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'postgres_e2e_support'

RSpec.describe PostgresE2ESupport do
  around do |example|
    original_value = ENV['PG_DATABASE_URL']
    example.run
  ensure
    original_value.nil? ? ENV.delete('PG_DATABASE_URL') : ENV['PG_DATABASE_URL'] = original_value
  end

  it 'uses PG_DATABASE_URL when configured' do
    ENV['PG_DATABASE_URL'] = 'postgresql://user:secret@localhost:5432/karya'

    expect(described_class.database_url).to eq('postgresql://user:secret@localhost:5432/karya')
  end

  it 'falls back to the default postgres database url' do
    ENV.delete('PG_DATABASE_URL')

    expect(described_class.database_url).to eq(described_class::DEFAULT_DATABASE_URL)
  end

  it 'yields the configured database url without provisioning a temporary database' do
    ENV['PG_DATABASE_URL'] = 'postgresql://user:secret@localhost:5432/karya'

    expect { |block| described_class.with_postgres_database(prefix: 'ignored', &block) }
      .to yield_with_args('postgresql://user:secret@localhost:5432/karya')
  end
end
