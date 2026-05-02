# frozen_string_literal: true

RSpec.describe Karya::Internal::ImmutableHookPayload do
  let(:error_class) { Karya::InvalidWorkerConfigurationError }

  it 'reuses already frozen string keys when snapshotting keys' do
    frozen_key = +'stage'
    frozen_key.freeze

    snapshot_key = described_class.send(:snapshot_key, frozen_key)

    expect(snapshot_key).to be(frozen_key)
  end

  it 'duplicates and freezes mutable string keys when snapshotting keys' do
    mutable_key = +'stage'

    snapshot_key = described_class.send(:snapshot_key, mutable_key)

    expect(snapshot_key).to eq(mutable_key)
    expect(snapshot_key).not_to be(mutable_key)
    expect(snapshot_key).to be_frozen
  end

  it 'rejects unsupported payload value types' do
    expect do
      described_class.snapshot({ bad: Object.new }, error_class:)
    end.to raise_error(
      Karya::InvalidWorkerConfigurationError,
      'payload values must be nil, booleans, numerics, strings, symbols, times, arrays, or hashes'
    )
  end

  it 'rejects payload keys outside the Symbol or String contract' do
    expect do
      described_class.snapshot({ [] => 'bad' }, error_class:)
    end.to raise_error(
      Karya::InvalidWorkerConfigurationError,
      'payload keys must be Symbols or Strings'
    )
  end

  it 'builds snapshot pairs with distinct top-level hashes and shared frozen nested values' do
    payload = { job_id: 'job-1', metadata: { 'stage' => 'ready' } }

    first_snapshot, second_snapshot = described_class.snapshot_pair(payload, error_class:)

    expect(first_snapshot).not_to be(second_snapshot)
    expect(first_snapshot).to eq(second_snapshot)
    expect(first_snapshot).to be_frozen
    expect(second_snapshot).to be_frozen
    expect(first_snapshot.fetch(:metadata)).to be(second_snapshot.fetch(:metadata))
    expect(first_snapshot.fetch(:job_id)).to be(second_snapshot.fetch(:job_id))
  end
end
