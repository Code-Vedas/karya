# frozen_string_literal: true

RSpec.describe Karya::Backend::InMemory do
  subject(:backend) { described_class.new }

  it 'exposes the in-memory backend descriptor' do
    descriptor = backend.descriptor

    expect(descriptor.identifier).to eq('in_memory')
    expect(descriptor).to be_frozen
  end

  it 'builds the queue store provider owned by the backend definition' do
    queue_store = backend.build_queue_store

    expect(queue_store).to be_a(Karya::QueueStore::InMemory)
  end

  it 'allows an injected queue store factory that returns a queue store base' do
    queue_store = Karya::QueueStore::InMemory.new
    queue_store_factory = Class.new do
      define_singleton_method(:new) { |**| queue_store }
    end
    backend = described_class.new(queue_store_class: queue_store_factory)

    expect(backend.build_queue_store).to be(queue_store)
  end

  it 'forwards provided queue-store builder keywords and omits nil values' do
    queue_store = Karya::QueueStore::InMemory.new
    captured_options = nil
    queue_store_factory = Class.new do
      define_singleton_method(:new) do |**options|
        captured_options = options
        queue_store
      end
    end
    backend = described_class.new(queue_store_class: queue_store_factory)
    token_generator = -> { 'token-1' }

    backend.build_queue_store(
      token_generator:,
      expired_tombstone_limit: 12,
      completed_batch_retention_limit: nil,
      max_batch_size: 50
    )

    expect(captured_options).to eq(
      token_generator:,
      expired_tombstone_limit: 12,
      max_batch_size: 50
    )
  end

  it 'rejects an injected queue store factory that returns a non queue store' do
    queue_store_factory = Class.new do
      define_singleton_method(:new) { |**| Object.new }
    end
    backend = described_class.new(queue_store_class: queue_store_factory)

    expect do
      backend.build_queue_store
    end.to raise_error(Karya::InvalidBackendSelectionError, /queue_store_class must build a Karya::QueueStore::Base/)
  end

  it 'declares no-op lifecycle hooks around queue-store usage' do
    queue_store = backend.build_queue_store

    expect(backend.before_start(queue_store:)).to be_nil
    expect(backend.after_stop(queue_store:)).to be_nil
  end
end
