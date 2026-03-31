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

  describe '#reserve' do
    it 'returns nil when the queue is empty' do
      expect(
        store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 1)
      ).to be_nil
    end

    it 'does not create queue entries when reserving from unknown queues' do
      3.times do |index|
        expect(
          store.reserve(
            queue: "missing-#{index}",
            worker_id: 'worker-1',
            lease_duration: 30,
            now: created_at + index + 1
          )
        ).to be_nil
      end

      expect(store_state.queued_job_ids_by_queue).to eq({})
    end

    it 'only reserves from the requested queue' do
      store.enqueue(job: submission_job(id: 'billing-1', queue: 'billing', created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'email-1', queue: 'email', created_at:), now: created_at + 2)

      reservation = store.reserve(queue: 'email', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)

      expect(reservation.job_id).to eq('email-1')
      expect(
        store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4).job_id
      ).to eq('billing-1')
    end

    it 'reserves jobs in FIFO order within the same queue' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'job-2', queue: 'billing', created_at:), now: created_at + 2)

      first = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)
      second = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4)

      expect(first.job_id).to eq('job-1')
      expect(second.job_id).to eq('job-2')
    end

    it 'returns a reservation lease with the reserved job metadata' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      expect(reservation).to be_a(Karya::Reservation)
      expect(reservation.token).to eq('lease-1:1')
      expect(reservation.job_id).to eq('job-1')
      expect(reservation.queue).to eq('billing')
      expect(reservation.worker_id).to eq('worker-1')
      expect(reservation.reserved_at).to eq(created_at + 2)
      expect(reservation.expires_at).to eq(created_at + 32)
    end

    it 'generates unique reservation tokens from repeated base token values without orphaning jobs' do
      token_sequence = %w[dup-token dup-token token-3 token-4].each
      duplicate_token_store = described_class.new(token_generator: -> { token_sequence.next })
      duplicate_token_store.enqueue(
        job: submission_job(id: 'job-1', queue: 'billing', created_at:),
        now: created_at + 1
      )
      duplicate_token_store.enqueue(
        job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1),
        now: created_at + 2
      )

      first_reservation = duplicate_token_store.reserve(
        queue: 'billing',
        worker_id: 'worker-1',
        lease_duration: 30,
        now: created_at + 3
      )
      second_reservation = duplicate_token_store.reserve(
        queue: 'billing',
        worker_id: 'worker-2',
        lease_duration: 30,
        now: created_at + 4
      )

      duplicate_token_store.release(reservation_token: first_reservation.token, now: created_at + 5)

      next_reservation = duplicate_token_store.reserve(
        queue: 'billing',
        worker_id: 'worker-3',
        lease_duration: 30,
        now: created_at + 6
      )
      duplicate_token_store.release(reservation_token: second_reservation.token, now: created_at + 7)
      reclaimed_reservation = duplicate_token_store.reserve(
        queue: 'billing',
        worker_id: 'worker-4',
        lease_duration: 30,
        now: created_at + 8
      )

      expect(second_reservation.token).to eq('dup-token:2')
      expect(second_reservation.token).not_to eq(first_reservation.token)
      expect(next_reservation.job_id).to eq('job-1')
      expect(reclaimed_reservation.job_id).to eq('job-2')
    end

    it 'prunes queue entries after reserving the last queued job' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)

      store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      expect(store_state.queued_job_ids_by_queue).to eq({})
    end

    it 'expires leases before reserving so reclaimed jobs can be reused deterministically' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 33)

      expect(reservation.job_id).to eq('job-1')
      expect(reservation.token).to eq('lease-2:2')
    end

    it 'rejects non-positive lease durations' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)

      expect do
        store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 0, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /lease_duration must be a positive number/)
    end

    it 'rejects non-finite lease durations without removing the queued job' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)

      expect do
        store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: Float::INFINITY, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /lease_duration must be a positive number/)

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 3)
      expect(reservation.job_id).to eq('job-1')
    end

    it 'rejects unsupported numeric lease durations' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)

      expect do
        store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: Complex(1, 0), now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /lease_duration must be a positive number/)
    end

    it 'rejects blank identifiers for reserve input' do
      expect do
        store.reserve(queue: ' ', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /queue must be present/)
    end

    it 'rejects blank worker_id for reserve input' do
      expect do
        store.reserve(queue: 'billing', worker_id: ' ', lease_duration: 30, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /worker_id must be present/)
    end

    it 'rejects nil worker_id for reserve input' do
      expect do
        store.reserve(queue: 'billing', worker_id: nil, lease_duration: 30, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /worker_id must be present/)
    end

    it 'rejects invalid timestamps for reserve input' do
      expect do
        store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: '2026-03-27T12:00:02Z')
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /now must be a Time/)
    end
  end
end
