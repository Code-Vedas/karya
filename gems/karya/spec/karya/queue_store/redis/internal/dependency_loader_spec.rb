# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::Redis.const_get(:Internal, false)::DependencyLoader do
  let(:dependency_loader) { described_class }

  it 'raises an actionable load error when the redis gem is unavailable' do
    original_error = LoadError.new('cannot load such file -- redis')
    allow(dependency_loader).to receive(:require).with('redis').and_raise(original_error)

    expect do
      dependency_loader.require_redis!
    end.to raise_error(
      LoadError,
      /Add `gem 'redis', '~> 5.4'` to your Gemfile to use Karya::Backend::Redis and Karya::QueueStore::Redis\./
    )
  end

  it 'preserves the original LoadError as the cause' do
    original_error = LoadError.new('cannot load such file -- redis')
    allow(dependency_loader).to receive(:require).with('redis').and_raise(original_error)

    dependency_loader.require_redis!
  rescue LoadError => e
    expect(e.cause).to be(original_error)
  else
    raise 'expected LoadError'
  end
end
