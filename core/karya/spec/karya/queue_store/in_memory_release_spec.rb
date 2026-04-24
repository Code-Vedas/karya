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

  describe '#release' do
    it 'returns an active reservation to the queue' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      queued_job = store.release(reservation_token: reservation.token, now: created_at + 3)
      next_reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4)

      expect(queued_job.state).to eq(:queued)
      expect(queued_job.updated_at).to eq(created_at + 3)
      expect(next_reservation.job_id).to eq('job-1')
    end

    it 'rejects unknown reservation tokens' do
      expect do
        store.release(reservation_token: 'missing-token', now: created_at + 1)
      end.to raise_error(Karya::UnknownReservationError, /was not found/)
    end

    it 'rejects blank reservation tokens as invalid release input' do
      expect do
        store.release(reservation_token: ' ', now: created_at + 1)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /reservation_token must be present/)
    end

    it 'rejects invalid timestamps for release input' do
      expect do
        store.release(reservation_token: 'missing-token', now: '2026-03-27T12:00:01Z')
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /now must be a Time/)
    end

    it 'rejects expired reservation tokens and requeues the job' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      expect do
        store.release(reservation_token: reservation.token, now: created_at + 32)
      end.to raise_error(Karya::ExpiredReservationError, /#{reservation.token}/)

      next_reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 33)
      expect(next_reservation.job_id).to eq('job-1')
    end

    it 'still reports expired reservation tokens after they have been reclaimed' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      store.expire_reservations(now: created_at + 32)

      expect do
        store.release(reservation_token: reservation.token, now: created_at + 33)
      end.to raise_error(Karya::ExpiredReservationError, /#{reservation.token}/)
    end
  end
end
