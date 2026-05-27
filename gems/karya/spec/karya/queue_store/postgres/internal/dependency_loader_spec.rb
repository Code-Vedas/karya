# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::Postgres.const_get(:Internal, false)::DependencyLoader do
  let(:dependency_loader) { described_class }

  it 'raises an actionable load error when pg is unavailable' do
    original_error = LoadError.new('cannot load such file -- pg')
    allow(dependency_loader).to receive(:require).with('pg').and_raise(original_error)

    expect do
      dependency_loader.require_pg!
    end.to raise_error(
      LoadError,
      /Add `gem 'pg'` to your Gemfile to use Karya::Backend::Postgres and Karya::QueueStore::Postgres\./
    )
  end

  it 'preserves the original cause' do
    original_error = LoadError.new('cannot load such file -- pg')
    allow(dependency_loader).to receive(:require).with('pg').and_raise(original_error)

    dependency_loader.require_pg!
  rescue LoadError => e
    expect(e.cause).to be(original_error)
  else
    raise 'expected LoadError'
  end
end
