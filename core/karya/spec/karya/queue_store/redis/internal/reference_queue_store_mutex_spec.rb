# frozen_string_literal: true

RSpec.describe Karya::QueueStore::Redis.const_get(:Internal, false)::ReferenceQueueStoreMutex do
  subject(:mutex) do
    described_class.new(owner:, persistence_mutex:)
  end

  let(:owner_class) do
    Class.new do
      def bypass_reference_queue_persistence?; end
    end
  end
  let(:owner) { instance_double(owner_class, bypass_reference_queue_persistence?: bypass_persistence) }
  let(:persistence_mutex) { instance_double(Karya::QueueStore::Redis.const_get(:Internal, false)::PersistenceMutex) }
  let(:bypass_persistence) { false }

  it 'routes event synchronization through the persistence mutex by default' do
    allow(persistence_mutex).to receive(:synchronize_with_event).and_yield.and_return(:persisted)

    result = mutex.synchronize_with_event(event_builder: ->(_) { { 'name' => 'enqueue' } }) { :event }

    expect(result).to eq(:persisted)
    expect(persistence_mutex).to have_received(:synchronize_with_event)
  end

  context 'when persistence is bypassed for the current thread' do
    let(:bypass_persistence) { true }

    it 'uses the read-only mutex for event synchronization' do
      allow(persistence_mutex).to receive(:synchronize_with_event)

      result = mutex.synchronize_with_event(event_builder: ->(_) { { 'name' => 'enqueue' } }) { :event }

      expect(result).to eq(:event)
      expect(persistence_mutex).not_to have_received(:synchronize_with_event)
    end
  end
end
