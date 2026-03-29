# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::InMemoryQueueStore do
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

  describe '#enqueue' do
    it 'transitions submission jobs to queued with the provided timestamp' do
      queued_job = store.enqueue(
        job: submission_job(id: 'job-1', queue: 'billing', created_at:),
        now: Time.utc(2026, 3, 27, 12, 0, 5)
      )

      expect(queued_job.state).to eq(:queued)
      expect(queued_job.updated_at).to eq(Time.utc(2026, 3, 27, 12, 0, 5))
    end

    it 'rejects duplicate job ids' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)

      expect do
        store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 2)
      end.to raise_error(Karya::DuplicateJobError, /job-1/)
    end

    it 'rejects jobs not in submission state' do
      queued_job = Karya::Job.new(
        id: 'job-1',
        queue: 'billing',
        handler: 'billing_sync',
        state: :queued,
        created_at:
      )

      expect do
        store.enqueue(job: queued_job, now: created_at + 1)
      end.to raise_error(Karya::InvalidEnqueueError, /submission/)
    end

    it 'rejects non-job values' do
      expect do
        store.enqueue(job: instance_double(Karya::Job), now: created_at + 1)
      end.to raise_error(Karya::InvalidEnqueueError, /Karya::Job/)
    end

    it 'rejects invalid timestamps' do
      expect do
        store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: '2026-03-27T12:00:01Z')
      end.to raise_error(Karya::InvalidEnqueueError, /now must be a Time/)
    end

    it 'expires old reservations before adding new jobs' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(
        queue: 'billing',
        worker_id: 'worker-1',
        lease_duration: 30,
        now: created_at + 2
      )

      store.enqueue(job: submission_job(id: 'job-2', queue: 'billing', created_at:), now: created_at + 40)

      next_reservation = store.reserve(
        queue: 'billing',
        worker_id: 'worker-2',
        lease_duration: 30,
        now: created_at + 41
      )

      expect(next_reservation.job_id).to eq(reservation.job_id)
    end

    it 'does not expire reservations when enqueue input is invalid' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(
        queue: 'billing',
        worker_id: 'worker-1',
        lease_duration: 30,
        now: created_at + 2
      )
      invalid_job = Karya::Job.new(
        id: 'job-2',
        queue: 'billing',
        handler: 'billing_sync',
        state: :queued,
        created_at:
      )

      expect do
        store.enqueue(job: invalid_job, now: created_at + 40)
      end.to raise_error(Karya::InvalidEnqueueError, /submission/)

      expect do
        store.release(reservation_token: reservation.token, now: created_at + 41)
      end.to raise_error(Karya::ExpiredReservationError, /#{reservation.token}/)

      reclaimed_reservation = store.reserve(
        queue: 'billing',
        worker_id: 'worker-2',
        lease_duration: 30,
        now: created_at + 42
      )

      expect(reclaimed_reservation.job_id).to eq('job-1')
    end
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

  describe '#start_execution' do
    it 'transitions a reserved job to running and increments the attempt count' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      running_job = store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      expect(running_job.state).to eq(:running)
      expect(running_job.attempt).to eq(1)
      expect(running_job.updated_at).to eq(created_at + 3)
      expect(store_state.reservations_by_token).to eq({})
      expect(store_state.executions_by_token.keys).to eq([reservation.token])
      expect(stored_job('job-1').state).to eq(:running)
    end

    it 'rejects unknown reservation tokens' do
      expect do
        store.start_execution(reservation_token: 'missing-token', now: created_at + 1)
      end.to raise_error(Karya::UnknownReservationError, /was not found/)
    end

    it 'rejects expired reservation tokens and requeues the job' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      expect do
        store.start_execution(reservation_token: reservation.token, now: created_at + 32)
      end.to raise_error(Karya::ExpiredReservationError, /#{reservation.token}/)

      reclaimed_reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 33)
      expect(reclaimed_reservation.job_id).to eq('job-1')
    end
  end

  describe '#complete_execution' do
    it 'finalizes a running job as succeeded and removes the active execution token' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      succeeded_job = store.complete_execution(reservation_token: reservation.token, now: created_at + 4)

      expect(succeeded_job.state).to eq(:succeeded)
      expect(succeeded_job.attempt).to eq(1)
      expect(succeeded_job.updated_at).to eq(created_at + 4)
      expect(store_state.executions_by_token).to eq({})
      expect(stored_job('job-1').state).to eq(:succeeded)
    end

    it 'rejects unknown execution tokens' do
      expect do
        store.complete_execution(reservation_token: 'missing-token', now: created_at + 1)
      end.to raise_error(Karya::UnknownReservationError, /was not found/)
    end
  end

  describe '#fail_execution' do
    it 'finalizes a running job as failed and preserves the incremented attempt count' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      failed_job = store.fail_execution(reservation_token: reservation.token, now: created_at + 4)

      expect(failed_job.state).to eq(:failed)
      expect(failed_job.attempt).to eq(1)
      expect(stored_job('job-1').state).to eq(:failed)
    end

    it 'rejects tokens that never entered execution' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      expect do
        store.fail_execution(reservation_token: reservation.token, now: created_at + 3)
      end.to raise_error(Karya::UnknownReservationError, /was not found/)
    end
  end

  describe '#expire_reservations' do
    it 'requeues expired reservations in deterministic order' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'job-2', queue: 'billing', created_at:), now: created_at + 2)

      first = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)
      second = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4)

      expired_jobs = store.expire_reservations(now: created_at + 40)

      expect(expired_jobs.map(&:id)).to eq([first.job_id, second.job_id])

      first_reclaimed = store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 30, now: created_at + 41)
      second_reclaimed = store.reserve(queue: 'billing', worker_id: 'worker-4', lease_duration: 30, now: created_at + 42)

      expect(first_reclaimed.job_id).to eq('job-1')
      expect(second_reclaimed.job_id).to eq('job-2')
    end

    it 'is idempotent when no reservations are expired' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      expect(store.expire_reservations(now: created_at + 10)).to eq([])
      expect(store.expire_reservations(now: created_at + 10)).to eq([])
    end

    it 'rejects invalid timestamps for expiration input' do
      expect do
        store.expire_reservations(now: '2026-03-27T12:00:10Z')
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /now must be a Time/)
    end

    it 'bounds expired reservation tombstones' do
      bounded_store = described_class.new(
        token_generator: %w[token-1 token-2 token-3].each.method(:next),
        expired_tombstone_limit: 2
      )

      3.times do |index|
        bounded_store.enqueue(
          job: submission_job(id: "job-#{index}", queue: 'billing', created_at: created_at + index),
          now: created_at + index + 1
        )
        bounded_store.reserve(
          queue: 'billing',
          worker_id: "worker-#{index}",
          lease_duration: 1,
          now: created_at + index + 2
        )
        bounded_store.expire_reservations(now: created_at + index + 3)
      end

      expired_tokens = bounded_store.instance_variable_get(:@state).expired_reservation_tokens
      expect(expired_tokens.keys).to eq(%w[token-2:2 token-3:3])
    end

    it 'does not let a stale token release a new reservation after tombstone pruning' do
      repeating_token_store = described_class.new(
        token_generator: -> { 'repeat' },
        expired_tombstone_limit: 1
      )
      repeating_token_store.enqueue(
        job: submission_job(id: 'job-1', queue: 'billing', created_at:),
        now: created_at + 1
      )
      repeating_token_store.enqueue(
        job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1),
        now: created_at + 2
      )

      first_reservation = repeating_token_store.reserve(
        queue: 'billing',
        worker_id: 'worker-1',
        lease_duration: 1,
        now: created_at + 3
      )
      repeating_token_store.expire_reservations(now: created_at + 5)

      second_reservation = repeating_token_store.reserve(
        queue: 'billing',
        worker_id: 'worker-2',
        lease_duration: 1,
        now: created_at + 6
      )
      repeating_token_store.expire_reservations(now: created_at + 8)

      third_reservation = repeating_token_store.reserve(
        queue: 'billing',
        worker_id: 'worker-3',
        lease_duration: 30,
        now: created_at + 9
      )

      expect(second_reservation.token).not_to eq(first_reservation.token)
      expect(third_reservation.token).not_to eq(first_reservation.token)
      expect do
        repeating_token_store.release(reservation_token: first_reservation.token, now: created_at + 10)
      end.to raise_error(Karya::UnknownReservationError, /#{first_reservation.token}/)
      expect(repeating_token_store.release(reservation_token: third_reservation.token, now: created_at + 11).id).to eq('job-1')
    end
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
