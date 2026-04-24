# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::RecoverySupport' do
  subject(:store) { store_class.new }

  let(:store_class) { Karya::QueueStore::InMemory }
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }

  def store_state
    store.instance_variable_get(:@state)
  end

  def submission_job
    Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      state: :submission,
      created_at:
    )
  end

  it 'requeues expired reservations and tombstones the token' do
    store.enqueue(job: submission_job, now: created_at + 1)
    reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

    queued_job = store.send(:requeue_expired_reservation, reservation, created_at + 5)

    expect(queued_job.state).to eq(:queued)
    expect(store_state.expired_reservation_tokens).to include(reservation.token)
  end
end
