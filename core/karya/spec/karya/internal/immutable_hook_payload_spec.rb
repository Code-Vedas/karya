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
end
