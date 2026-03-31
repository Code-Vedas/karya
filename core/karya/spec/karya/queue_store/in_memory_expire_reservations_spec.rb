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

    it 'requeues running jobs whose execution lease expires' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 5, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      expired_jobs = store.expire_reservations(now: created_at + 10)
      reclaimed_reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 11)

      expect(expired_jobs.map(&:id)).to eq(['job-1'])
      expect(stored_job('job-1').state).to eq(:reserved)
      expect(reclaimed_reservation.job_id).to eq('job-1')
    end

    it 'requeues recovered running jobs through a valid lifecycle transition' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 2.5)

      recovered_jobs = store.expire_reservations(now: created_at + 5)

      expect(recovered_jobs.map(&:state)).to eq([:queued])
      expect(stored_job('job-1').can_transition_to?(:reserved)).to be(true)
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
end
