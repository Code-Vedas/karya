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

  describe 'store state helpers' do
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

    it 'rejects reservation tokens that collide with active or expired tracking' do
      store_state.reservations_by_token['active-token'] = instance_double(Karya::Reservation)
      store_state.expired_reservation_tokens['expired-token'] = true

      expect do
        store.send(:ensure_unique_reservation_token, 'active-token')
      end.to raise_error(Karya::DuplicateReservationTokenError, /active or expired/)

      expect do
        store.send(:ensure_unique_reservation_token, 'expired-token')
      end.to raise_error(Karya::DuplicateReservationTokenError, /active or expired/)
    end
  end
end
