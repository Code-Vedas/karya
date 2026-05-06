# frozen_string_literal: true

RSpec.describe Karya::QueueStore::Redis::Internal::DependencyLoader do
  it 'raises an actionable load error when the redis gem is unavailable' do
    original_error = LoadError.new('cannot load such file -- redis')
    allow(described_class).to receive(:require).with('redis').and_raise(original_error)

    expect do
      described_class.require_redis!
    end.to raise_error(
      LoadError,
      /Add `gem 'redis', '~> 5.4'` to your Gemfile to use Karya::Backend::Redis and Karya::QueueStore::Redis\./
    )
  end

  it 'preserves the original LoadError as the cause' do
    original_error = LoadError.new('cannot load such file -- redis')
    allow(described_class).to receive(:require).with('redis').and_raise(original_error)

    described_class.require_redis!
  rescue LoadError => e
    expect(e.cause).to be(original_error)
  else
    raise 'expected LoadError'
  end
end
