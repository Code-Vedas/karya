# frozen_string_literal: true

RSpec.describe Karya::Backend::InMemory do
  subject(:backend) { described_class.new }

  it 'exposes the quick setup descriptor and non-durable capability posture' do
    descriptor = backend.descriptor

    expect(descriptor.identifier).to eq('in_memory')
    expect(descriptor.classification).to eq(:quick_setup_and_run)
    expect(descriptor.quick_setup_and_run?).to be(true)
    expect(descriptor.capabilities.job_persistence?).to be(false)
    expect(descriptor.capabilities.workflow_state?).to be(false)
    expect(descriptor.capabilities.schedule_state?).to be(false)
    expect(descriptor.capabilities.audit_history?).to be(false)
    expect(descriptor.capabilities.shared_processes?).to be(false)
    expect(descriptor.capabilities.multi_node?).to be(false)
    expect(descriptor.capabilities.parity_exceptions).not_to be_empty
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

  it 'declares no-op lifecycle hooks around queue-store usage' do
    queue_store = backend.build_queue_store

    expect(backend.before_start(queue_store:)).to be_nil
    expect(backend.after_stop(queue_store:)).to be_nil
  end
end
