# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::StoreState' do
  subject(:store_state) { described_class.new(expired_tombstone_limit: 16) }

  let(:described_class) do
    Karya::QueueStore::InMemory.const_get(:Internal, false).const_get(:StoreState, false)
  end

  it 'ignores execution tokens that are not present' do
    store_state.execution_tokens_in_order << 'lease-1'

    store_state.delete_execution_token('missing-token')

    expect(store_state.execution_tokens_in_order).to eq(['lease-1'])
  end

  it 'does nothing when deleting a reservation token that is not in the ordering array' do
    expect(store_state.delete_reservation_token('missing-token')).to be_nil
  end

  it 'does not duplicate expired reservation tombstones' do
    store_state.mark_expired('expired-token')

    expect do
      store_state.mark_expired('expired-token')
    end.not_to(change(store_state, :expired_reservation_tokens_in_order))
  end

  it 'does not duplicate retry-pending job ids' do
    expect(store_state.register_retry_pending('job-1')).to eq(['job-1'])

    expect do
      store_state.register_retry_pending('job-1')
    end.not_to(change(store_state, :retry_pending_job_ids))

    expect(store_state.register_retry_pending('job-1')).to eq(['job-1'])
  end

  it 'keeps batches with missing member jobs during terminal batch pruning' do
    store_state.batches_by_id['batch-1'] = Karya::Workflow::Batch.new(
      id: 'batch-1',
      job_ids: ['missing-job'],
      created_at: Time.utc(2026, 4, 1, 12, 0, 0)
    )

    store_state.prune_terminal_batches(0)

    expect(store_state.batches_by_id.keys).to eq(['batch-1'])
  end
end
