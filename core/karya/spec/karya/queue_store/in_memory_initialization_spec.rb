# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::InMemory do
  subject(:store) { described_class.new(token_generator: token_generator) }

  let(:token_sequence) { %w[lease-1 lease-2 lease-3 lease-4].each }
  let(:token_generator) { -> { token_sequence.next } }
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }

  def submission_job(id:, queue:, created_at:, handler: 'billing_sync')
    Karya::Job.new(
      id:,
      queue:,
      handler:,
      state: :submission,
      created_at:
    )
  end

  def stored_job(id)
    store_state.jobs_by_id.fetch(id)
  end

  def store_state
    store.instance_variable_get(:@state)
  end

  describe '#initialize' do
    it 'rejects negative expired tombstone limits' do
      expect do
        described_class.new(expired_tombstone_limit: -1)
      end.to raise_error(ArgumentError, /finite non-negative Integer/)
    end

    it 'rejects nil expired tombstone limits' do
      expect do
        described_class.new(expired_tombstone_limit: nil)
      end.to raise_error(ArgumentError, /finite non-negative Integer/)
    end

    it 'rejects non-integer expired tombstone limits' do
      expect do
        described_class.new(expired_tombstone_limit: Float::INFINITY)
      end.to raise_error(ArgumentError, /finite non-negative Integer/)
    end
  end

  describe 'internal state helpers' do
    it 'ignores execution tokens that are not present' do
      store_state.execution_tokens_in_order << 'lease-1'

      store_state.delete_execution_token('missing-token')

      expect(store_state.execution_tokens_in_order).to eq(['lease-1'])
    end
  end
end
