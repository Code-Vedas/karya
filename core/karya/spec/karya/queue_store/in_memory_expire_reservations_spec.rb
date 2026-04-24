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
  let(:retry_policy) { Karya::RetryPolicy.new(max_attempts: 3, base_delay: 5, multiplier: 2) }

  def submission_job(id:, queue:, created_at:, handler: 'billing_sync')
    Karya::Job.new(
      id:,
      queue:,
      handler:,
      state: :submission,
      created_at:
    )
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

    it 'requeues running jobs whose execution lease expires' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 5, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      expired_jobs = store.expire_reservations(now: created_at + 10)
      reclaimed_reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 11)

      expect(expired_jobs.map(&:id)).to eq(['job-1'])
      expect(reclaimed_reservation.job_id).to eq('job-1')
    end

    it 'requeues recovered running jobs through a valid lifecycle transition' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 2.5)

      recovered_jobs = store.expire_reservations(now: created_at + 5)

      expect(recovered_jobs.map(&:state)).to eq([:queued])
      expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 6)&.job_id).to eq('job-1')
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

  describe '#recover_in_flight' do
    it 'reports expired jobs and recovered reserved and running jobs separately' do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-expired',
          queue: 'email',
          handler: 'billing_sync',
          state: :submission,
          created_at:,
          expires_at: created_at + 6
        ),
        now: created_at + 1
      )
      store.enqueue(job: submission_job(id: 'job-reserved', queue: 'billing', created_at:), now: created_at + 2)
      store.enqueue(job: submission_job(id: 'job-running', queue: 'billing', created_at:), now: created_at + 3)

      reserved = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 3, now: created_at + 4)
      running = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 1, now: created_at + 5)
      store.start_execution(reservation_token: running.token, now: created_at + 5.5)

      report = store.recover_in_flight(now: created_at + 10)

      expect(report).to be_a(Karya::QueueStore::RecoveryReport)
      expect(report.recovered_at).to eq(created_at + 10)
      expect(report.expired_jobs.map(&:id)).to eq(['job-expired'])
      expect(report.recovered_reserved_jobs.map(&:id)).to eq([reserved.job_id])
      expect(report.recovered_running_jobs.map(&:id)).to eq([running.job_id])
      expect(report.jobs.map(&:id)).to eq(%w[job-expired job-reserved job-running])
    end

    it 'reports expired retry-pending jobs with queued job expirations' do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-retry-expired',
          queue: 'billing',
          handler: 'billing_sync',
          retry_policy:,
          state: :submission,
          created_at:,
          expires_at: created_at + 8
        ),
        now: created_at + 1
      )
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(reservation_token: reservation.token, now: created_at + 4, retry_policy:, failure_classification: :error)

      report = store.recover_in_flight(now: created_at + 9)

      expect(report.expired_jobs.map(&:id)).to eq(['job-retry-expired'])
      expect(report.recovered_reserved_jobs).to eq([])
      expect(report.recovered_running_jobs).to eq([])
      expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 10)).to be_nil
    end

    it 'preserves running attempt counts when execution leases are recovered' do
      store.enqueue(job: submission_job(id: 'job-running', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 2.5)

      report = store.recover_in_flight(now: created_at + 5)

      expect(report.recovered_running_jobs.first.attempt).to eq(1)
    end

    it 'recovers only the requested worker orphan set' do
      store.enqueue(job: submission_job(id: 'job-worker-1', queue: 'billing', created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'job-worker-2', queue: 'billing', created_at:), now: created_at + 2)
      store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 2, now: created_at + 3)
      store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 1, now: created_at + 4)

      recovered_jobs = store.recover_orphaned_jobs(worker_id: 'worker-1', now: created_at + 8)

      expect(recovered_jobs.map(&:id)).to eq(['job-worker-1'])
      expect(store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 30, now: created_at + 9)&.job_id).to eq('job-worker-1')
    end

    it 'does not expire unrelated queued jobs during worker-scoped orphan recovery' do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-expired',
          queue: 'email',
          handler: 'billing_sync',
          state: :submission,
          created_at:,
          expires_at: created_at + 4
        ),
        now: created_at + 1
      )
      store.enqueue(job: submission_job(id: 'job-worker-1', queue: 'billing', created_at: created_at + 1), now: created_at + 2)
      store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 3)

      recovered_jobs = store.recover_orphaned_jobs(worker_id: 'worker-1', now: created_at + 8)

      expect(recovered_jobs.map(&:id)).to eq(['job-worker-1'])
    end

    it 'tombstones recovered reserved and running tokens' do
      store.enqueue(job: submission_job(id: 'job-reserved', queue: 'billing', created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'job-running', queue: 'billing', created_at:), now: created_at + 2)
      reserved = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 3)
      running = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 1, now: created_at + 4)
      store.start_execution(reservation_token: running.token, now: created_at + 4.5)

      store.recover_in_flight(now: created_at + 8)

      expect do
        store.release(reservation_token: reserved.token, now: created_at + 9)
      end.to raise_error(Karya::ExpiredReservationError, /#{reserved.token}/)
      expect do
        store.complete_execution(reservation_token: running.token, now: created_at + 9)
      end.to raise_error(Karya::ExpiredReservationError, /#{running.token}/)
    end

    it 'rejects invalid timestamps for recovery input' do
      expect do
        store.recover_in_flight(now: '2026-03-27T12:00:10Z')
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /now must be a Time/)
    end
  end
end
