# frozen_string_literal: true

RSpec.describe Karya::QueueStore::Redis.const_get(:Internal, false)::PersistenceMutex do
  subject(:mutex) do
    persistence_mutex_class.new(
      redis:,
      owner:,
      state_key: 'redis:test:state',
      lock_key: 'redis:test:lock',
      version_key: 'redis:test:version'
    )
  end

  let(:persistence_mutex_class) { described_class }
  let(:redis) { instance_double(Redis) }
  let(:owner_class) do
    Class.new do
      def load_persisted_state; end
      def dump_state_payload(applied_version:); end
      def snapshot_persisted(version); end
      def dump_event_payload(event); end
      def event_persisted(version); end
      def namespace; end
      def restore_authoritative_state_after_failure; end
    end
  end
  let(:owner) do
    instance_double(
      owner_class,
      load_persisted_state: nil,
      dump_state_payload: 'payload',
      snapshot_persisted: nil,
      dump_event_payload: 'event-payload',
      event_persisted: nil,
      namespace: 'redis:test',
      restore_authoritative_state_after_failure: nil
    )
  end

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
    allow(redis).to receive(:set).with('redis:test:lock', 'token-timeout', nx: true, ex: persistence_mutex_class::LOCK_TTL_SECONDS).and_return(nil)
    allow(redis).to receive(:eval)
    allow(Kernel).to receive(:sleep)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0.0, 1.0, 2.0, 3.0, 4.0, 5.0)

    expect do
      mutex.send(:with_distributed_lock) { nil }
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'timed out acquiring Redis queue-store lock')

    expect(Kernel).to have_received(:sleep).with(persistence_mutex_class::LOCK_POLL_INTERVAL).once
    expect(Kernel).to have_received(:sleep).with(persistence_mutex_class::LOCK_POLL_INTERVAL * 2).once
    expect(Kernel).to have_received(:sleep).with(persistence_mutex_class::LOCK_POLL_INTERVAL * 4).once
    expect(Kernel).to have_received(:sleep).with(persistence_mutex_class::LOCK_POLL_INTERVAL * 8).once
    expect(redis).not_to have_received(:eval)
  end

  it 'preserves acquisition failures instead of masking them in ensure cleanup' do
    allow(SecureRandom).to receive(:uuid).and_return('token-acquire-error')
    allow(redis).to receive(:set).with(
      'redis:test:lock',
      'token-acquire-error',
      nx: true,
      ex: persistence_mutex_class::LOCK_TTL_SECONDS
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

    expect(mutex.send(:extend_lock?, 'token-1')).to be(true)
    expect(redis).to have_received(:eval).with(
      persistence_mutex_class::EXTEND_SCRIPT,
      keys: ['redis:test:lock'],
      argv: ['token-1', persistence_mutex_class::LOCK_TTL_SECONDS.to_s]
    )
  end

  it 'fails fast when lock extension script execution fails' do
    allow(redis).to receive(:eval).and_raise(RuntimeError, 'eval failed')
    allow(redis).to receive(:get)
    allow(redis).to receive(:expire)

    expect do
      mutex.send(:extend_lock?, 'token-2')
    end.to raise_error(RuntimeError, 'eval failed')

    expect(redis).not_to have_received(:get)
    expect(redis).not_to have_received(:expire)
  end

  it 'starts and stops the lock renewal thread cooperatively' do
    allow(redis).to receive(:eval).and_return(1)

    stop_signal = Queue.new
    renewal_thread = mutex.send(:start_lock_renewal, 'token-4', stop_signal)

    expect(renewal_thread).to be_a(Thread)
    stop_signal.push(true)
    renewal_thread.join
    expect(renewal_thread).not_to be_alive
  end

  it 'stops the renewal loop when lock extension returns false' do
    fake_thread = instance_double(Thread, join: nil, alive?: false)
    allow(Thread).to receive(:new) do |&block|
      block.call
      fake_thread
    end
    stop_signal = instance_double(Queue)
    allow(stop_signal).to receive(:pop).with(timeout: persistence_mutex_class::LOCK_RENEW_INTERVAL).and_return(nil, nil)
    allow(redis).to receive(:eval).with(
      persistence_mutex_class::EXTEND_SCRIPT,
      keys: ['redis:test:lock'],
      argv: ['token-stop', persistence_mutex_class::LOCK_TTL_SECONDS.to_s]
    ).and_return(1, 0)

    renewal_thread = mutex.send(:start_lock_renewal, 'token-stop', stop_signal)

    expect(renewal_thread).to eq(fake_thread)
    expect(stop_signal).to have_received(:pop).with(timeout: persistence_mutex_class::LOCK_RENEW_INTERVAL).twice
    expect(mutex.send(:lock_lost?)).to be(true)
  end

  it 'treats renewal wait timeouts as the normal path to the next extension attempt' do
    fake_thread = instance_double(Thread, join: nil, alive?: false)
    allow(Thread).to receive(:new) do |&block|
      block.call
      fake_thread
    end
    stop_signal = instance_double(Queue)
    pop_calls = 0
    allow(stop_signal).to receive(:pop).with(timeout: persistence_mutex_class::LOCK_RENEW_INTERVAL) do
      pop_calls += 1
      raise ThreadError if pop_calls == 1

      true
    end
    allow(redis).to receive(:eval).with(
      persistence_mutex_class::EXTEND_SCRIPT,
      keys: ['redis:test:lock'],
      argv: ['token-timeout', persistence_mutex_class::LOCK_TTL_SECONDS.to_s]
    ).and_return(1)

    renewal_thread = mutex.send(:start_lock_renewal, 'token-timeout', stop_signal)

    expect(renewal_thread).to eq(fake_thread)
    expect(stop_signal).to have_received(:pop).with(timeout: persistence_mutex_class::LOCK_RENEW_INTERVAL).twice
    expect(mutex.send(:lock_lost?)).to be(false)
  end

  it 'swallows renewal thread errors after attempting an extension' do
    stop_signal = instance_double(Queue)
    allow(stop_signal).to receive(:pop).with(timeout: persistence_mutex_class::LOCK_RENEW_INTERVAL).and_return(nil)
    allow(redis).to receive(:eval).and_raise(RuntimeError, 'eval failed')

    renewal_thread = mutex.send(:start_lock_renewal, 'token-5', stop_signal)
    renewal_thread.join

    expect(redis).to have_received(:eval).with(
      persistence_mutex_class::EXTEND_SCRIPT,
      keys: ['redis:test:lock'],
      argv: ['token-5', persistence_mutex_class::LOCK_TTL_SECONDS.to_s]
    )
    expect(renewal_thread).not_to be_alive
  end

  it 'does not persist state for read-only synchronized operations' do
    fake_thread = instance_double(Thread, join: nil)
    allow(SecureRandom).to receive(:uuid).and_return('token-read-only')
    allow(redis).to receive(:set).with('redis:test:lock', 'token-read-only', nx: true, ex: persistence_mutex_class::LOCK_TTL_SECONDS).and_return('OK')
    allow(Thread).to receive(:new).and_return(fake_thread)
    allow(redis).to receive(:get).with('redis:test:lock').and_return('token-read-only')
    allow(redis).to receive(:eval).and_return(1)
    allow(owner).to receive(:load_persisted_state)
    allow(owner).to receive(:dump_state_payload)

    result = mutex.read_only_synchronize { :snapshot }

    expect(result).to eq(:snapshot)
    expect(owner).to have_received(:load_persisted_state)
    expect(owner).not_to have_received(:dump_state_payload)
  end

  it 'skips snapshot persistence when persist_if rejects the block result' do
    fake_thread = instance_double(Thread, join: nil)
    allow(SecureRandom).to receive(:uuid).and_return('token-skip-snapshot')
    allow(redis).to receive(:set).with('redis:test:lock', 'token-skip-snapshot', nx: true, ex: persistence_mutex_class::LOCK_TTL_SECONDS).and_return('OK')
    allow(Thread).to receive(:new).and_return(fake_thread)
    allow(redis).to receive(:get).with('redis:test:lock').and_return('token-skip-snapshot')
    allow(redis).to receive(:eval).and_return(1)
    allow(owner).to receive(:load_persisted_state)
    allow(owner).to receive(:dump_state_payload)

    result = mutex.synchronize(persist_if: ->(_result) { false }) { :snapshot }

    expect(result).to eq(:snapshot)
    expect(owner).to have_received(:load_persisted_state)
    expect(owner).not_to have_received(:dump_state_payload)
  end

  it 'skips event persistence when persist_if rejects the block result' do
    fake_thread = instance_double(Thread, join: nil)
    allow(SecureRandom).to receive(:uuid).and_return('token-skip-event')
    allow(redis).to receive(:set).with('redis:test:lock', 'token-skip-event', nx: true, ex: persistence_mutex_class::LOCK_TTL_SECONDS).and_return('OK')
    allow(Thread).to receive(:new).and_return(fake_thread)
    allow(redis).to receive(:get).with('redis:test:lock').and_return('token-skip-event')
    allow(redis).to receive(:eval).and_return(1)
    allow(owner).to receive(:load_persisted_state)
    allow(owner).to receive(:dump_event_payload)

    result = mutex.synchronize_with_event(
      event_builder: ->(_result) { { 'name' => 'enqueue' } },
      persist_if: ->(_result) { false }
    ) { :event }

    expect(result).to eq(:event)
    expect(owner).to have_received(:load_persisted_state)
    expect(owner).not_to have_received(:dump_event_payload)
  end

  it 'raises for read-only synchronized operations when the lock is no longer held after the block' do
    fake_thread = instance_double(Thread, join: nil)
    allow(SecureRandom).to receive(:uuid).and_return('token-read-only-lost')
    allow(redis).to receive(:set).with('redis:test:lock', 'token-read-only-lost', nx: true, ex: persistence_mutex_class::LOCK_TTL_SECONDS).and_return('OK')
    allow(Thread).to receive(:new).and_return(fake_thread)
    allow(redis).to receive(:get).with('redis:test:lock').and_return(nil)
    allow(redis).to receive(:eval).and_return(1)
    allow(owner).to receive(:load_persisted_state)
    allow(owner).to receive(:dump_state_payload)

    expect do
      mutex.read_only_synchronize { :snapshot }
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lost Redis queue-store lock during mutation')

    expect(owner).to have_received(:load_persisted_state)
    expect(owner).not_to have_received(:dump_state_payload)
  end

  it 'restores owner state after read-only synchronization raises from the block' do
    fake_thread = instance_double(Thread, join: nil)
    allow(SecureRandom).to receive(:uuid).and_return('token-read-only-error')
    allow(redis).to receive(:set).with('redis:test:lock', 'token-read-only-error', nx: true, ex: persistence_mutex_class::LOCK_TTL_SECONDS).and_return('OK')
    allow(Thread).to receive(:new).and_return(fake_thread)
    allow(redis).to receive(:eval).and_return(1)
    allow(redis).to receive(:get).with('redis:test:lock').and_return('token-read-only-error')

    expect do
      mutex.read_only_synchronize { raise Karya::InvalidQueueStoreOperationError, 'boom' }
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'boom')

    expect(owner).to have_received(:restore_authoritative_state_after_failure)
  end

  it 'restores owner state after read-only synchronization raises ExpiredReservationError' do
    fake_thread = instance_double(Thread, join: nil)
    allow(SecureRandom).to receive(:uuid).and_return('token-read-only-expired')
    allow(redis).to receive(:set).with('redis:test:lock', 'token-read-only-expired', nx: true, ex: persistence_mutex_class::LOCK_TTL_SECONDS).and_return('OK')
    allow(Thread).to receive(:new).and_return(fake_thread)
    allow(redis).to receive(:eval).and_return(1)

    expect do
      mutex.read_only_synchronize { raise Karya::ExpiredReservationError, 'reservation "lease-1" has expired' }
    end.to raise_error(Karya::ExpiredReservationError, 'reservation "lease-1" has expired')

    expect(owner).to have_received(:restore_authoritative_state_after_failure)
  end

  it 'aborts persistence when the renewal loop loses the distributed lock' do
    allow(redis).to receive_messages(
      set: 'OK',
      eval: 1
    )
    allow(redis).to receive(:get).with('redis:test:lock').and_return('different-token')
    allow(owner).to receive(:load_persisted_state)
    allow(owner).to receive(:dump_state_payload)

    expect do
      mutex.synchronize do
        mutex.send(:record_lock_loss, RuntimeError.new('eval failed'))
        :done
      end
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lost Redis queue-store lock during mutation: eval failed')

    expect(owner).to have_received(:load_persisted_state)
    expect(owner).not_to have_received(:dump_state_payload)
  end

  it 'persists a snapshot before re-raising expired reservation errors in event mode' do
    fake_thread = instance_double(Thread, join: nil)
    allow(SecureRandom).to receive(:uuid).and_return('token-expired-event')
    allow(redis).to receive(:set).with('redis:test:lock', 'token-expired-event', nx: true, ex: persistence_mutex_class::LOCK_TTL_SECONDS).and_return('OK')
    allow(Thread).to receive(:new).and_return(fake_thread)
    allow(redis).to receive(:get).with('redis:test:lock').and_return('token-expired-event')
    allow(redis).to receive(:get).with('redis:test:version').and_return(nil)
    allow(redis).to receive(:eval).and_return(1, 1)
    allow(owner).to receive(:dump_state_payload).with(applied_version: 1).and_return('payload')

    expect do
      mutex.synchronize_with_event(event_builder: ->(_result) { raise 'unused' }) do
        raise Karya::ExpiredReservationError, 'reservation "lease-1" has expired'
      end
    end.to raise_error(Karya::ExpiredReservationError, 'reservation "lease-1" has expired')

    expect(owner).to have_received(:dump_state_payload).with(applied_version: 1)
    expect(owner).to have_received(:snapshot_persisted).with(1)
    expect(owner).not_to have_received(:restore_authoritative_state_after_failure)
  end

  it 'restores owner state when expired event recovery snapshot persistence fails' do
    fake_thread = instance_double(Thread, join: nil)
    allow(SecureRandom).to receive(:uuid).and_return('token-expired-event-persist-fail')
    allow(redis).to receive(:set).with(
      'redis:test:lock',
      'token-expired-event-persist-fail',
      nx: true,
      ex: persistence_mutex_class::LOCK_TTL_SECONDS
    ).and_return('OK')
    allow(Thread).to receive(:new).and_return(fake_thread)
    allow(redis).to receive(:get).with('redis:test:lock').and_return('token-expired-event-persist-fail')
    allow(redis).to receive(:get).with('redis:test:version').and_return(nil)
    allow(redis).to receive(:eval).and_return(0, 1)
    allow(owner).to receive(:dump_state_payload).with(applied_version: 1).and_return('payload')

    expect do
      mutex.synchronize_with_event(event_builder: ->(_result) { raise 'unused' }) do
        raise Karya::ExpiredReservationError, 'reservation "lease-3" has expired'
      end
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lost Redis queue-store lock during mutation')

    expect(owner).to have_received(:restore_authoritative_state_after_failure)
  end

  it 'raises lock loss instead of persisting expired event recovery after the lock is lost' do
    fake_thread = instance_double(Thread, join: nil)
    allow(SecureRandom).to receive(:uuid).and_return('token-expired-event-lost')
    allow(redis).to receive(:set).with('redis:test:lock', 'token-expired-event-lost', nx: true, ex: persistence_mutex_class::LOCK_TTL_SECONDS).and_return('OK')
    allow(Thread).to receive(:new).and_return(fake_thread)
    allow(redis).to receive(:eval).and_return(1)

    expect do
      mutex.synchronize_with_event(event_builder: ->(_result) { raise 'unused' }) do
        mutex.send(:record_lock_loss, RuntimeError.new('renewal failed'))
        raise Karya::ExpiredReservationError, 'reservation "lease-2" has expired'
      end
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lost Redis queue-store lock during mutation: renewal failed')

    expect(owner).not_to have_received(:snapshot_persisted)
  end

  it 'swallows owner restore failures while reverting local state' do
    allow(owner).to receive(:restore_authoritative_state_after_failure).and_raise(StandardError, 'reload failed')

    expect(mutex.send(:restore_owner_state_after_failure)).to be_nil
  end

  it 'resets prior lock-loss state before a new distributed-lock acquisition' do
    fake_thread = instance_double(Thread, join: nil)
    allow(SecureRandom).to receive(:uuid).and_return('token-reset')
    allow(redis).to receive(:set).with('redis:test:lock', 'token-reset', nx: true, ex: persistence_mutex_class::LOCK_TTL_SECONDS).and_return('OK')
    allow(Thread).to receive(:new).and_return(fake_thread)
    allow(redis).to receive(:eval).and_return(1)

    mutex.send(:record_lock_loss, RuntimeError.new('stale loss'))

    mutex.send(:with_distributed_lock) do
      expect(mutex.send(:lock_lost?)).to be(false)
    end

    expect(redis).to have_received(:eval).with(
      persistence_mutex_class::RELEASE_SCRIPT,
      keys: ['redis:test:lock'],
      argv: ['token-reset']
    )
  end

  it 're-checks lock ownership immediately before persisting state' do
    fake_thread = instance_double(Thread, join: nil)
    allow(SecureRandom).to receive(:uuid).and_return('token-recheck')
    allow(redis).to receive(:set).with('redis:test:lock', 'token-recheck', nx: true, ex: persistence_mutex_class::LOCK_TTL_SECONDS).and_return('OK')
    allow(Thread).to receive(:new).and_return(fake_thread)
    allow(redis).to receive(:get).with('redis:test:lock').and_return(nil)
    allow(redis).to receive(:eval).and_return(0, 1)
    allow(owner).to receive(:load_persisted_state)
    allow(owner).to receive(:dump_state_payload).and_return('payload')

    expect do
      mutex.synchronize { :done }
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lost Redis queue-store lock during mutation')

    expect(owner).to have_received(:load_persisted_state)
    expect(owner).not_to have_received(:dump_state_payload)
  end

  it 'records lock loss when atomic persistence script execution raises' do
    fake_thread = instance_double(Thread, join: nil)
    allow(SecureRandom).to receive(:uuid).and_return('token-persist-error')
    allow(redis).to receive(:set).with('redis:test:lock', 'token-persist-error', nx: true, ex: persistence_mutex_class::LOCK_TTL_SECONDS).and_return('OK')
    allow(Thread).to receive(:new).and_return(fake_thread)
    allow(redis).to receive(:get).with('redis:test:lock').and_return('token-persist-error')
    allow(redis).to receive(:get).with('redis:test:version').and_return('0')
    allow(redis).to receive(:eval).and_raise(RuntimeError, 'persist boom')
    allow(owner).to receive(:load_persisted_state)
    allow(owner).to receive(:dump_state_payload).and_return('payload')

    expect do
      mutex.synchronize { :done }
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lost Redis queue-store lock during mutation: persist boom')
  end

  it 'returns when verify_lock_still_held sees the current token' do
    mutex.instance_variable_set(:@current_lock_token, 'token-held')
    allow(redis).to receive(:get).with('redis:test:lock').and_return('token-held')

    expect(mutex.send(:verify_lock_still_held)).to be_nil
  end

  it 'raises when verify_lock_still_held sees a stolen lock' do
    mutex.instance_variable_set(:@current_lock_token, 'token-lost')
    allow(redis).to receive(:get).with('redis:test:lock').and_return('other-token')

    expect do
      mutex.send(:verify_lock_still_held)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lost Redis queue-store lock during mutation')
  end

  it 'persists state only when the distributed lock still matches the current token' do
    fake_thread = instance_double(Thread, join: nil)
    allow(SecureRandom).to receive(:uuid).and_return('token-persist')
    allow(redis).to receive(:set).with('redis:test:lock', 'token-persist', nx: true, ex: persistence_mutex_class::LOCK_TTL_SECONDS).and_return('OK')
    allow(Thread).to receive(:new).and_return(fake_thread)
    allow(redis).to receive(:get).with('redis:test:lock').and_return('token-persist')
    allow(redis).to receive(:get).with('redis:test:version').and_return('0')
    allow(redis).to receive(:eval).and_return(1)
    allow(owner).to receive(:load_persisted_state)
    allow(owner).to receive(:dump_state_payload).and_return('payload')

    expect(mutex.synchronize { :done }).to eq(:done)
    expect(redis).to have_received(:eval).with(
      persistence_mutex_class::PERSIST_SNAPSHOT_SCRIPT,
      keys: ['redis:test:lock', 'redis:test:version', 'redis:test:state'],
      argv: ['token-persist', 'payload', persistence_mutex_class::LOCK_TTL_SECONDS.to_s]
    )
  end

  it 'raises lock loss when atomic persistence reports that the lock is no longer owned' do
    mutex.instance_variable_set(:@current_lock_token, 'token-stale')
    allow(owner).to receive(:dump_state_payload).and_return('payload')
    allow(redis).to receive(:get).with('redis:test:version').and_return('0')
    allow(redis).to receive(:eval).with(
      persistence_mutex_class::PERSIST_SNAPSHOT_SCRIPT,
      keys: ['redis:test:lock', 'redis:test:version', 'redis:test:state'],
      argv: ['token-stale', 'payload', persistence_mutex_class::LOCK_TTL_SECONDS.to_s]
    ).and_return(0)

    expect do
      mutex.send(:persist_snapshot_if_owned)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lost Redis queue-store lock during mutation')
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

  it 'does not fall back to non-atomic delete when release script execution fails' do
    allow(redis).to receive(:eval).and_raise(RuntimeError, 'eval failed')
    allow(redis).to receive(:get)
    allow(redis).to receive(:del)

    expect(mutex.send(:release_lock, 'token-release')).to be_nil
    expect(redis).not_to have_received(:get)
    expect(redis).not_to have_received(:del)
  end

  it 'returns false when compact_snapshot script execution raises' do
    mutex.instance_variable_set(:@current_lock_token, 'token-compact')
    allow(redis).to receive(:eval).and_raise(RuntimeError, 'compact boom')

    expect(mutex.compact_snapshot(payload: 'snapshot')).to be(false)
  end

  it 'raises for unsupported persistence modes' do
    expect do
      mutex.send(:persist_if_owned, mode: :mystery, event_builder: nil, persist_if: nil, result: nil)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported Redis persistence mode/)
  end

  it 'raises lock loss when atomic event persistence reports that the lock is no longer owned' do
    mutex.instance_variable_set(:@current_lock_token, 'token-event-stale')
    allow(owner).to receive(:dump_event_payload).with({ 'name' => 'enqueue' }).and_return('event-payload')
    allow(redis).to receive(:eval).with(
      persistence_mutex_class::APPEND_EVENT_SCRIPT,
      keys: ['redis:test:lock', 'redis:test:version'],
      argv: ['token-event-stale', 'redis:test:queue_store:event:', 'event-payload', persistence_mutex_class::LOCK_TTL_SECONDS.to_s]
    ).and_return(0)

    expect do
      mutex.send(:persist_event_if_owned, { 'name' => 'enqueue' })
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lost Redis queue-store lock during mutation')
  end

  it 'records lock loss when atomic event persistence script execution raises' do
    mutex.instance_variable_set(:@current_lock_token, 'token-event-error')
    allow(owner).to receive(:dump_event_payload).with({ 'name' => 'enqueue' }).and_return('event-payload')
    allow(redis).to receive(:eval).and_raise(RuntimeError, 'event boom')

    expect do
      mutex.send(:persist_event_if_owned, { 'name' => 'enqueue' })
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lost Redis queue-store lock during mutation: event boom')
  end
end
