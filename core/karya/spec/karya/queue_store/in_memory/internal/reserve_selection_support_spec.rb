# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::ReserveSelectionSupport::FairQueueOrder' do
  let(:described_class) do
    Karya::QueueStore::InMemory
      .const_get(:Internal, false)
      .const_get(:ReserveSelectionSupport, false)
      .const_get(:FairQueueOrder, false)
  end

  it 'returns queues unchanged for strict-order scans' do
    ordered_queues = %w[billing email]

    result = described_class.new(
      queues: ordered_queues,
      strategy: :strict_order,
      last_reserved_queue: 'billing'
    ).to_a

    expect(result).to eq(ordered_queues)
  end

  it 'returns a single queue unchanged for round-robin scans' do
    ordered_queues = ['billing']

    result = described_class.new(
      queues: ordered_queues,
      strategy: :round_robin,
      last_reserved_queue: 'billing'
    ).to_a

    expect(result).to eq(ordered_queues)
  end
end
