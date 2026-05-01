# frozen_string_literal: true

RSpec.describe Karya::Internal::ImmutableHookPayload do
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
end
