# frozen_string_literal: true

require 'bigdecimal'

RSpec.describe Karya::QueueStore::Redis.const_get(:Internal, false)::StateSnapshot do
  subject(:state_snapshot) { described_class }

  let(:json_codec) { state_snapshot.const_get(:JsonCodec, false) }
  let(:store_state_class) { Karya::QueueStore::Internal.const_get(:StoreState, false) }
  let(:created_at) { Time.utc(2026, 5, 5, 12, 0, 0) }
  let(:redis_url) { 'redis://example.test:6379/0' }
  let(:namespace) { 'redis-snapshot' }
  let(:fake_redis_client_class) do
    Class.new do
      attr_reader :data

      def initialize
        @data = {}
      end

      def get(key)
        data[key]
      end

      def set(key, value, **options)
        if options.fetch(:nx, false)
          return nil if data.key?(key)

          data[key] = value
          return 'OK'
        end

        data[key] = value
        'OK'
      end

      def del(key)
        data.delete(key) ? 1 : 0
      end

      def expire(key, _seconds)
        data.key?(key) ? 1 : 0
      end

      def eval(_script, keys:, argv:)
        key = keys.fetch(0)
        token = argv.fetch(0)
        return 0 unless get(key) == token

        if keys.length == 2
          data[keys.fetch(1)] = argv.fetch(1)
          1
        else
          del(key)
        end
      end
    end
  end
  let(:redis_client) { fake_redis_client_class.new }

  before do
    allow(Redis).to receive(:new).with(url: redis_url).and_return(redis_client)
  end

  def build_store
    store = Karya::QueueStore::Redis.new(url: redis_url, namespace:)
    job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      arguments: {
        'amount' => BigDecimal('12.34'),
        'ratio' => Rational(2, 3),
        'note' => 'frozen-value'
      },
      state: :submission,
      created_at:
    )
    store.enqueue(job:, now: created_at + 1)
    store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 2)
    store
  end

  it 'round-trips a persisted queue-store snapshot through the JSON codec' do
    store = build_store
    payload = state_snapshot.dump(
      state: store.instance_variable_get(:@state),
      reservation_token_sequence: 7
    )

    snapshot = state_snapshot.load(payload)
    restored_job = snapshot.fetch(:state).jobs_by_id.fetch('job-1')

    expect(snapshot.fetch(:state)).to be_a(store_state_class)
    expect(snapshot.fetch(:reservation_token_sequence)).to eq(7)
    expect(restored_job).to be_a(Karya::Job)
    expect(restored_job.state).to eq(:reserved)
    expect(restored_job.can_transition_to?(:running)).to be(true)
    expect(restored_job.arguments.fetch('amount')).to eq(BigDecimal('12.34'))
    expect(restored_job.arguments.fetch('ratio')).to eq(Rational(2, 3))
    expect(restored_job.arguments.fetch('note')).to eq('frozen-value')
    expect(restored_job.arguments.fetch('note')).to be_frozen
    expect(restored_job.arguments.keys.first).to be_frozen
  end

  it 'rejects invalid JSON payloads' do
    expect do
      state_snapshot.load('not-json')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid Redis state snapshot: JSON::ParserError:/)
  end

  it 'rejects valid JSON payloads with invalid decode shape' do
    expect do
      state_snapshot.load('{"__karya_type__":"array","items":"not-an-array"}')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid Redis state snapshot: NoMethodError:/)
  end

  it 'preserves the original decode error as the cause' do
    state_snapshot.load('{"__karya_type__":"array","items":"not-an-array"}')
    raise 'expected load to fail'
  rescue Karya::InvalidQueueStoreOperationError => e
    expect(e.cause).to be_a(NoMethodError)
  end

  it 'rejects tampered payloads that request unsupported classes' do
    payload = <<~JSON
      {"__karya_type__":"object","class":"Thread::Mutex","ivars":{},"frozen":false}
    JSON

    expect do
      state_snapshot.load(payload)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported Redis state snapshot class/)
  end

  it 'round-trips top-level arrays in the JSON codec' do
    expect(json_codec.send(:decode_value, [1, { '__karya_type__' => 'symbol', 'value' => 'queued' }])).to eq([1, :queued])
  end

  it 'decodes plain hashes without tagged metadata' do
    expect(json_codec.send(:decode_tagged_value, { 'state' => { '__karya_type__' => 'symbol', 'value' => 'queued' } })).to eq('state' => :queued)
  end

  it 'rejects tagged symbols outside the bounded Redis snapshot symbol set' do
    expect do
      json_codec.send(:decode_tagged_value, { '__karya_type__' => 'symbol', 'value' => 'karya_uninterned_snapshot_symbol' })
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported Redis state snapshot symbol/)
  end

  it 'round-trips supported Numeric payloads without losing precision' do
    payload = json_codec.dump(
      'amount' => BigDecimal('999999999999999999.1234'),
      'ratio' => Rational(7, 9)
    )

    decoded = json_codec.load(payload)

    expect(decoded.fetch('amount')).to eq(BigDecimal('999999999999999999.1234'))
    expect(decoded.fetch('ratio')).to eq(Rational(7, 9))
  end

  it 'passes through finite Float scalars' do
    expect(json_codec.send(:encode_value, 1.5)).to eq(1.5)
  end

  it 'freezes decoded String scalars and hash keys' do
    decoded = json_codec.load('{"status":"queued","__karya_type__":"hash","entries":[["name","billing"],["state","queued"]],"frozen":true}')

    expect(decoded).to be_frozen
    expect(decoded.keys).to all(be_frozen)
    expect(decoded.values).to all(satisfy { |value| !value.is_a?(String) || value.frozen? })
  end

  it 'rejects Symbol job arguments during snapshot encoding' do
    job = Karya::Job.new(
      id: 'job-symbol',
      queue: 'billing',
      handler: 'billing_sync',
      arguments: { 'kind' => :symbol_value },
      state: :submission,
      created_at:
    )

    expect do
      json_codec.send(:encode_value, job)
    end.to raise_error(
      Karya::InvalidQueueStoreOperationError,
      'Redis queue-store snapshots do not support Symbol job arguments'
    )
  end

  it 'rejects non-finite Float job arguments during snapshot encoding' do
    job = Karya::Job.new(
      id: 'job-nan',
      queue: 'billing',
      handler: 'billing_sync',
      arguments: { 'value' => Float::NAN },
      state: :submission,
      created_at:
    )

    expect do
      json_codec.send(:encode_value, job)
    end.to raise_error(
      Karya::InvalidQueueStoreOperationError,
      'Redis queue-store snapshots do not support non-finite Float job arguments'
    )
  end

  it 'rejects Symbol job arguments nested inside arrays' do
    job = Karya::Job.new(
      id: 'job-symbol-array',
      queue: 'billing',
      handler: 'billing_sync',
      arguments: { 'items' => [:manual] },
      state: :submission,
      created_at:
    )

    expect do
      json_codec.send(:encode_value, job)
    end.to raise_error(
      Karya::InvalidQueueStoreOperationError,
      'Redis queue-store snapshots do not support Symbol job arguments'
    )
  end

  it 'rejects unsupported object payloads during generic object encoding' do
    expect do
      json_codec.send(:encode_karya_object, Object.new)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported Redis state snapshot payload: Object/)
  end

  it 'rejects unsupported struct payloads during generic struct encoding' do
    anonymous_struct = Struct.new(:value).new(1)

    expect do
      json_codec.send(:encode_karya_struct, anonymous_struct)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported Redis state snapshot payload:/)
  end

  it 'rejects unsupported top-level decode payloads' do
    expect do
      json_codec.send(:decode_value, Object.new)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported Redis state snapshot payload: Object/)
  end

  it 'rejects unknown tagged payload types' do
    expect do
      json_codec.send(:decode_tagged_value, { '__karya_type__' => 'mystery' })
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported Redis state snapshot payload type/)
  end

  it 'rejects forbidden Karya classes during restore' do
    expect do
      json_codec.send(:resolve_karya_class, 'Karya::JobLifecycle::Registry')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported Redis state snapshot class/)
  end

  it 'rejects missing Karya classes during restore' do
    expect do
      json_codec.send(:resolve_karya_class, 'Karya::MissingSnapshotClass')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported Redis state snapshot class/)
  end

  it 'rejects unrelated Karya classes during restore' do
    expect do
      json_codec.send(:resolve_karya_class, 'Karya::Backend::InMemory')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported Redis state snapshot class/)
  end

  it 'rejects invalid snapshot shapes' do
    expect do
      state_snapshot.send(:validate_snapshot, [])
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'invalid Redis state snapshot')
  end

  it 'rejects snapshot hashes missing required keys' do
    expect do
      state_snapshot.send(:validate_snapshot, { state: build_store.instance_variable_get(:@state) })
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'invalid Redis state snapshot')
  end
end
