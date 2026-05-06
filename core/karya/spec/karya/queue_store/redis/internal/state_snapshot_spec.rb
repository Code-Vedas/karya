# frozen_string_literal: true

RSpec.describe Karya::QueueStore::Redis::Internal::StateSnapshot do
  let(:json_codec) { described_class.const_get(:JsonCodec, false) }
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

        del(key)
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
      state: :submission,
      created_at:
    )
    store.enqueue(job:, now: created_at + 1)
    store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 2)
    store
  end

  it 'round-trips a persisted queue-store snapshot through the JSON codec' do
    store = build_store
    payload = described_class.dump(
      state: store.instance_variable_get(:@state),
      reservation_token_sequence: 7
    )

    snapshot = described_class.load(payload)
    restored_job = snapshot.fetch(:state).jobs_by_id.fetch('job-1')

    expect(snapshot.fetch(:state)).to be_a(store_state_class)
    expect(snapshot.fetch(:reservation_token_sequence)).to eq(7)
    expect(restored_job).to be_a(Karya::Job)
    expect(restored_job.state).to eq(:reserved)
    expect(restored_job.can_transition_to?(:running)).to be(true)
  end

  it 'rejects invalid JSON payloads' do
    expect do
      described_class.load('not-json')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid Redis state snapshot/)
  end

  it 'rejects valid JSON payloads with invalid decode shape' do
    expect do
      described_class.load('{"__karya_type__":"array","items":"not-an-array"}')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid Redis state snapshot/)
  end

  it 'rejects tampered payloads that request unsupported classes' do
    payload = <<~JSON
      {"__karya_type__":"object","class":"Thread::Mutex","ivars":{},"frozen":false}
    JSON

    expect do
      described_class.load(payload)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported Redis state snapshot class/)
  end

  it 'round-trips top-level arrays in the JSON codec' do
    expect(json_codec.send(:decode_value, [1, { '__karya_type__' => 'symbol', 'value' => 'queued' }])).to eq([1, :queued])
  end

  it 'decodes plain hashes without tagged metadata' do
    expect(json_codec.send(:decode_tagged_value, { 'state' => { '__karya_type__' => 'symbol', 'value' => 'queued' } })).to eq('state' => :queued)
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

  it 'rejects invalid snapshot shapes' do
    expect do
      described_class.send(:validate_snapshot, [])
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'invalid Redis state snapshot')
  end

  it 'rejects snapshot hashes missing required keys' do
    expect do
      described_class.send(:validate_snapshot, { state: build_store.instance_variable_get(:@state) })
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'invalid Redis state snapshot')
  end
end
