# frozen_string_literal: true

RSpec.describe Karya::QueueStore::Redis::Internal::DependencyLoader do
  it 'raises an actionable load error when the redis gem is unavailable' do
    allow(described_class).to receive(:require).with('redis').and_raise(LoadError, 'cannot load such file -- redis')

    expect do
      described_class.require_redis!
    end.to raise_error(
      LoadError,
      /Add `gem 'redis', '~> 5.4'` to your Gemfile to use Karya::Backend::Redis and Karya::QueueStore::Redis\./
    )
  end
end
