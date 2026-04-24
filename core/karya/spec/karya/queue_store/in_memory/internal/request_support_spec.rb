# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::RequestSupport' do
  subject(:store) { store_class.new(token_generator: token_generator) }

  let(:store_class) { Karya::QueueStore::InMemory }
  let(:token_sequence) { %w[lease-1 lease-2].each }
  let(:token_generator) { -> { token_sequence.next } }

  def store_state
    store.instance_variable_get(:@state)
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
