# frozen_string_literal: true

RSpec.describe Karya::QueueStore::Redis::Internal::PersistenceMutex do
  subject(:mutex) do
    described_class.new(
      redis:,
      owner:,
      state_key: 'redis:test:state',
      lock_key: 'redis:test:lock'
    )
  end

  let(:redis) { instance_double(Redis) }
  let(:owner) { Object.new }

  it 'does not attempt lock cleanup when token allocation fails before acquisition starts' do
    allow(SecureRandom).to receive(:uuid).and_raise(RuntimeError, 'uuid failure')
    allow(redis).to receive(:set)
    allow(redis).to receive(:eval)
    allow(redis).to receive(:get)
    allow(redis).to receive(:del)

    expect do
      mutex.send(:with_distributed_lock) { nil }
    end.to raise_error(RuntimeError, 'uuid failure')

    expect(redis).not_to have_received(:set)
    expect(redis).not_to have_received(:eval)
    expect(redis).not_to have_received(:get)
    expect(redis).not_to have_received(:del)
  end
end
