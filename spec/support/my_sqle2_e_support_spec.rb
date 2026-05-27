# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'mysql_e2e_support'

RSpec.describe MySQLE2ESupport do
  around do |example|
    original_value = ENV['MYSQL_DATABASE_URL']
    example.run
  ensure
    original_value.nil? ? ENV.delete('MYSQL_DATABASE_URL') : ENV['MYSQL_DATABASE_URL'] = original_value
  end

  it 'uses MYSQL_DATABASE_URL when configured' do
    ENV['MYSQL_DATABASE_URL'] = 'mysql2://root:secret@localhost:3306/karya'

    expect(described_class.database_url).to eq('mysql2://root:secret@localhost:3306/karya')
  end

  it 'falls back to the default mysql database url' do
    ENV.delete('MYSQL_DATABASE_URL')

    expect(described_class.database_url).to eq(described_class::DEFAULT_DATABASE_URL)
  end

  it 'yields the configured database url without provisioning a temporary database' do
    ENV['MYSQL_DATABASE_URL'] = 'mysql2://root:secret@localhost:3306/karya'

    expect { |block| described_class.with_mysql_database(prefix: 'ignored', &block) }
      .to yield_with_args('mysql2://root:secret@localhost:3306/karya')
  end
end
