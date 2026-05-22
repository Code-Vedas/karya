# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../../../../lib/karya/queue_store/internal/reference_queue_store'

RSpec.describe 'Karya::QueueStore::Internal::ReferenceQueueStore::Internal::ReserveSelectionSupport::FairQueueOrder' do
  let(:described_class) do
    Karya::QueueStore::Internal::ReferenceQueueStore
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

  it 'does not expose persisted reserve-selection hooks' do
    reserve_selection_support =
      Karya::QueueStore::Internal::ReferenceQueueStore
      .const_get(:Internal, false)
      .const_get(:ReserveSelectionSupport, false)
    store = Object.new.extend(reserve_selection_support)

    expect(store.private_methods).not_to include(:durable_reserve_direct_selection?, :durable_reserve_candidate_job_ids, :matching_durable_job_for)
  end

  it 'covers direct fairness guard branches on the reserve-selection module' do
    support = Karya::QueueStore::Internal::ReferenceQueueStore.const_get(:Internal, false).const_get(:ReserveSelectionSupport, false)
    helper_class = Class.new do
      include support

      def initialize(strategy:)
        @fairness_policy = Struct.new(:strategy).new(strategy)
        state_class = Struct.new(:last_reserved_queue_by_subscription, keyword_init: true) do
          def last_reserved_queue_for(subscription_key)
            last_reserved_queue_by_subscription[subscription_key]
          end
        end
        @state = state_class.new(last_reserved_queue_by_subscription: { 'sub' => 'billing' })
      end

      private

      attr_reader :fairness_policy, :state

      def track_fairness_history?(_queues)
        true
      end
    end

    strict = helper_class.new(strategy: :strict_order)
    round_robin = helper_class.new(strategy: :round_robin)

    expect(strict.send(:fair_queue_order, %w[billing email], 'sub')).to eq(%w[billing email])
    expect(round_robin.send(:fair_queue_order, ['billing'], 'sub')).to eq(['billing'])
  end
end
