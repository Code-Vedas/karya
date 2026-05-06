# frozen_string_literal: true

RSpec.describe Karya::QueueStore::Redis::Internal::PersistenceMutex do
  subject(:mutex) do
    described_class.new(
      redis:,
      owner:,
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

  it 'times out lock acquisition with bounded backoff' do
    allow(SecureRandom).to receive(:uuid).and_return('token-timeout')
    allow(redis).to receive(:set).with('redis:test:lock', 'token-timeout', nx: true, ex: described_class::LOCK_TTL_SECONDS).and_return(nil)
    allow(redis).to receive(:eval)
    allow(Kernel).to receive(:sleep)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0.0, 1.0, 2.0, 3.0, 4.0, 5.0)

    expect do
      mutex.send(:with_distributed_lock) { nil }
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'timed out acquiring Redis queue-store lock')

    expect(Kernel).to have_received(:sleep).with(described_class::LOCK_POLL_INTERVAL).once
    expect(Kernel).to have_received(:sleep).with(described_class::LOCK_POLL_INTERVAL * 2).once
    expect(Kernel).to have_received(:sleep).with(described_class::LOCK_POLL_INTERVAL * 4).once
    expect(Kernel).to have_received(:sleep).with(described_class::LOCK_POLL_INTERVAL * 8).once
    expect(redis).not_to have_received(:eval)
  end

  it 'preserves acquisition failures instead of masking them in ensure cleanup' do
    allow(SecureRandom).to receive(:uuid).and_return('token-acquire-error')
    allow(redis).to receive(:set).with(
      'redis:test:lock',
      'token-acquire-error',
      nx: true,
      ex: described_class::LOCK_TTL_SECONDS
    ).and_raise(RuntimeError, 'set failure')
    allow(redis).to receive(:eval)
    allow(redis).to receive(:get)
    allow(redis).to receive(:del)

    expect do
      mutex.send(:with_distributed_lock) { nil }
    end.to raise_error(RuntimeError, 'set failure')

    expect(redis).not_to have_received(:eval)
    expect(redis).not_to have_received(:get)
    expect(redis).not_to have_received(:del)
  end

  it 'extends the held lock when the primary eval succeeds' do
    allow(redis).to receive(:eval).and_return(1)

    expect(mutex.send(:extend_lock, 'token-1')).to be(true)
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

    expect(mutex.send(:extend_lock, 'token-2')).to be(true)
  end

  it 'does not extend another process lock when eval fallback sees a different token' do
    allow(redis).to receive(:eval).and_raise(RuntimeError, 'eval failed')
    allow(redis).to receive(:get).with('redis:test:lock').and_return('other-token')
    allow(redis).to receive(:expire)

    expect(mutex.send(:extend_lock, 'token-3')).to be(false)
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

  it 'stops the renewal loop when lock extension returns false' do
    fake_thread = instance_double(Thread, kill: nil, join: nil, alive?: false)
    allow(Thread).to receive(:new) do |&block|
      block.call
      fake_thread
    end
    allow(Kernel).to receive(:sleep)
    allow(redis).to receive(:eval).with(
      described_class::EXTEND_SCRIPT,
      keys: ['redis:test:lock'],
      argv: ['token-stop', described_class::LOCK_TTL_SECONDS.to_s]
    ).and_return(1, 0)

    renewal_thread = mutex.send(:start_lock_renewal, 'token-stop')

    expect(renewal_thread).to eq(fake_thread)
    expect(Kernel).to have_received(:sleep).with(described_class::LOCK_RENEW_INTERVAL).twice
    expect(mutex.send(:lock_lost?)).to be(true)
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

  it 'aborts persistence when the renewal loop loses the distributed lock' do
    allow(redis).to receive(:set).and_return('OK')
    allow(redis).to receive(:get).with('redis:test:lock').and_return('different-token')
    allow(redis).to receive(:eval).and_raise(RuntimeError, 'eval failed')
    allow(owner).to receive(:load_persisted_state)
    allow(owner).to receive(:persist_state)
    allow(Kernel).to receive(:sleep)

    expect do
      mutex.synchronize do
        mutex.send(:extend_lock, 'token-manual')
        mutex.send(:record_lock_loss)
        :done
      end
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lost Redis queue-store lock during mutation')

    expect(owner).to have_received(:load_persisted_state)
    expect(owner).not_to have_received(:persist_state)
  end

  it 'resets prior lock-loss state before a new distributed-lock acquisition' do
    fake_thread = instance_double(Thread, kill: nil, join: nil)
    allow(SecureRandom).to receive(:uuid).and_return('token-reset')
    allow(redis).to receive(:set).with('redis:test:lock', 'token-reset', nx: true, ex: described_class::LOCK_TTL_SECONDS).and_return('OK')
    allow(Thread).to receive(:new).and_return(fake_thread)
    allow(redis).to receive(:eval).and_return(1)

    mutex.send(:record_lock_loss, RuntimeError.new('stale loss'))

    mutex.send(:with_distributed_lock) do
      expect(mutex.send(:lock_lost?)).to be(false)
    end

    expect(redis).to have_received(:eval).with(
      described_class::RELEASE_SCRIPT,
      keys: ['redis:test:lock'],
      argv: ['token-reset']
    )
  end

  it 're-checks lock ownership immediately before persisting state' do
    fake_thread = instance_double(Thread, kill: nil, join: nil)
    allow(SecureRandom).to receive(:uuid).and_return('token-recheck')
    allow(redis).to receive(:set).with('redis:test:lock', 'token-recheck', nx: true, ex: described_class::LOCK_TTL_SECONDS).and_return('OK')
    allow(Thread).to receive(:new).and_return(fake_thread)
    allow(redis).to receive(:get).with('redis:test:lock').and_return(nil)
    allow(redis).to receive(:eval).and_return(1)
    allow(owner).to receive(:load_persisted_state)
    allow(owner).to receive(:persist_state)

    expect do
      mutex.synchronize { :done }
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lost Redis queue-store lock during mutation')

    expect(owner).to have_received(:load_persisted_state)
    expect(owner).not_to have_received(:persist_state)
  end

  it 'raises a generic lock-loss message when the lock disappears without a recorded cause' do
    mutex.send(:record_lock_loss)

    expect do
      mutex.send(:raise_lock_loss)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lost Redis queue-store lock during mutation')
  end

  it 'keeps the first recorded lock-loss cause' do
    first_error = RuntimeError.new('first cause')
    second_error = RuntimeError.new('second cause')

    mutex.send(:record_lock_loss, first_error)
    mutex.send(:record_lock_loss, second_error)

    expect do
      mutex.send(:raise_lock_loss)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lost Redis queue-store lock during mutation: first cause')
  end
end
