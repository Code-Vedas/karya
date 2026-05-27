# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::Config::RuntimeContext do
  it 'builds a default context from environment values' do
    context = described_class.default(
      env: { 'RAILS_ENV' => ' production ' },
      root_path: '/tmp/app'
    )

    expect(context.environment_name).to eq('production')
    expect(context.root_path.to_s).to eq('/tmp/app')
  end

  it 'falls back to development when no environment key is present' do
    expect(described_class.environment_name_from({})).to eq('development')
  end

  it 'skips blank environment values until it finds a configured one' do
    env = { 'KARYA_ENV' => ' ', 'RAILS_ENV' => '', 'HANAMI_ENV' => 'test' }

    expect(described_class.environment_name_from(env)).to eq('test')
  end

  it 'resolves relative and absolute paths' do
    context = described_class.new(root_path: '/tmp/app', environment_name: 'test')

    expect(context.resolve_path('config/karya.yml')).to eq('/tmp/app/config/karya.yml')
    expect(context.resolve_path('/etc/karya.yml')).to eq('/etc/karya.yml')
  end
end
