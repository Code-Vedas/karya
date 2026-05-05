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

  it 'extends the held lock when the primary eval succeeds' do
    allow(redis).to receive(:eval).and_return(1)

    expect(mutex.send(:extend_lock, 'token-1')).to eq(1)
    expect(redis).to have_received(:eval).with(
      described_class::EXTEND_SCRIPT,
      keys: ['redis:test:lock'],
      argv: ['token-1', described_class::LOCK_TTL_SECONDS.to_s]
    )
  end

  it 'falls back to expire when eval fails but the caller still owns the lock' do
    allow(redis).to receive(:eval).and_raise(RuntimeError, 'eval failed')
    allow(redis).to receive(:get).with('redis:test:lock').and_return('token-2')
    allow(redis).to receive(:expire).with('redis:test:lock', described_class::LOCK_TTL_SECONDS).and_return(1)

    expect(mutex.send(:extend_lock, 'token-2')).to eq(1)
  end

  it 'does not extend another process lock when eval fallback sees a different token' do
    allow(redis).to receive(:eval).and_raise(RuntimeError, 'eval failed')
    allow(redis).to receive(:get).with('redis:test:lock').and_return('other-token')
    allow(redis).to receive(:expire)

    expect(mutex.send(:extend_lock, 'token-3')).to be_nil
    expect(redis).not_to have_received(:expire)
  end

  it 'starts and stops the lock renewal thread cleanly' do
    allow(redis).to receive(:eval).and_return(1)
    allow(redis).to receive(:get)
    allow(redis).to receive(:expire)

    renewal_thread = mutex.send(:start_lock_renewal, 'token-4')

    expect(renewal_thread).to be_a(Thread)
    renewal_thread.kill.join
    expect(renewal_thread).not_to be_alive
  end

  it 'swallows renewal thread errors after attempting an extension' do
    allow(Kernel).to receive(:sleep).with(described_class::LOCK_RENEW_INTERVAL).and_return(nil)
    allow(redis).to receive(:eval).and_raise(RuntimeError, 'eval failed')
    allow(redis).to receive(:get).with('redis:test:lock').and_return('token-5')
    allow(redis).to receive(:expire)
      .with('redis:test:lock', described_class::LOCK_TTL_SECONDS)
      .and_raise(RuntimeError, 'expire failed')

    renewal_thread = mutex.send(:start_lock_renewal, 'token-5')
    renewal_thread.join

    expect(redis).to have_received(:eval).with(
      described_class::EXTEND_SCRIPT,
      keys: ['redis:test:lock'],
      argv: ['token-5', described_class::LOCK_TTL_SECONDS.to_s]
    )
    expect(renewal_thread).not_to be_alive
  end
end
