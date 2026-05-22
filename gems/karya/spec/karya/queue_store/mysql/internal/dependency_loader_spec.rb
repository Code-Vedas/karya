# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::MySQL.const_get(:Internal, false)::DependencyLoader do
  let(:dependency_loader) { described_class }

  it 'raises an actionable load error when mysql2 is unavailable' do
    original_error = LoadError.new('cannot load such file -- mysql2')
    allow(dependency_loader).to receive(:require).with('mysql2').and_raise(original_error)

    expect do
      dependency_loader.require_mysql2!
    end.to raise_error(
      LoadError,
      /Add `gem 'mysql2'` to your Gemfile to use Karya::Backend::MySQL and Karya::QueueStore::MySQL\./
    )
  end

  it 'preserves the original cause' do
    original_error = LoadError.new('cannot load such file -- mysql2')
    allow(dependency_loader).to receive(:require).with('mysql2').and_raise(original_error)

    dependency_loader.require_mysql2!
  rescue LoadError => e
    expect(e.cause).to be(original_error)
  else
    raise 'expected LoadError'
  end
end
