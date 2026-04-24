# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::LeaseDuration' do
  let(:described_class) do
    Karya::QueueStore::InMemory.const_get(:Internal, false).const_get(:LeaseDuration, false)
  end

  it 'accepts positive rational durations' do
    expect(described_class.new(Rational(3, 2)).normalize).to eq(Rational(3, 2))
  end

  it 'rejects non-finite float durations' do
    expect do
      described_class.new(Float::INFINITY).normalize
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /lease_duration must be a positive number/)
  end
end
