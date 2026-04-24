# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::ExecutionSupport' do
  subject(:store) { store_class.new }

  let(:store_class) { Karya::QueueStore::InMemory }
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }

  def store_state
    store.instance_variable_get(:@state)
  end

  it 'collects only expired execution leases' do
    reservation = Karya::Reservation.new(
      token: 'lease-1',
      job_id: 'job-1',
      queue: 'billing',
      worker_id: 'worker-1',
      reserved_at: created_at + 1,
      expires_at: created_at + 2
    )
    store_state.executions_by_token[reservation.token] = reservation
    store_state.execution_tokens_in_order << reservation.token

    expired = store.send(
      :collect_expired_leases,
      store_state.executions_by_token,
      store_state.execution_tokens_in_order,
      created_at + 3
    )

    expect(expired).to eq([reservation])
  end
end
