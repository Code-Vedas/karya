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

  describe '#enqueue' do
    it 'transitions submission jobs to queued with the provided timestamp' do
      queued_job = store.enqueue(
        job: submission_job(id: 'job-1', queue: 'billing', created_at:),
        now: Time.utc(2026, 3, 27, 12, 0, 5)
      )

      expect(queued_job.state).to eq(:queued)
      expect(queued_job.updated_at).to eq(Time.utc(2026, 3, 27, 12, 0, 5))
      expect(stored_job('job-1')).to eq(queued_job)
      expect(store_state.queued_job_ids_by_queue.fetch('billing')).to eq(['job-1'])
    end

    it 'rejects duplicate job ids' do
      original_job = store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)

      expect do
        store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 2)
      end.to raise_error(Karya::DuplicateJobError, /job-1/)

      expect(stored_job('job-1')).to eq(original_job)
      expect(store_state.queued_job_ids_by_queue.fetch('billing')).to eq(['job-1'])
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

      expect(store_state.jobs_by_id).to eq({})
      expect(store_state.queued_job_ids_by_queue).to eq({})
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
end
