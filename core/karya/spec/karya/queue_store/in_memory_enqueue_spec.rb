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

  def submission_job(
    id:,
    queue:,
    created_at:,
    handler: 'billing_sync',
    idempotency_key: nil,
    uniqueness_key: nil,
    uniqueness_scope: nil
  )
    Karya::Job.new(
      id:,
      queue:,
      handler:,
      idempotency_key:,
      uniqueness_key:,
      uniqueness_scope:,
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

    it 'rejects duplicate uniqueness keys while queued' do
      original_job = store.enqueue(
        job: submission_job(
          id: 'job-1',
          queue: 'billing',
          created_at:,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :queued
        ),
        now: created_at + 1
      )

      expect do
        store.enqueue(
          job: submission_job(
            id: 'job-2',
            queue: 'billing',
            created_at: created_at + 1,
            uniqueness_key: 'billing:account-42',
            uniqueness_scope: :queued
          ),
          now: created_at + 2
        )
      end.to raise_error(Karya::DuplicateUniquenessKeyError, /billing:account-42/)

      expect(stored_job('job-1')).to eq(original_job)
      expect(store_state.jobs_by_id.keys).to eq(['job-1'])
      expect(store_state.queued_job_ids_by_queue.fetch('billing')).to eq(['job-1'])
    end

    it 'does not recover expired reservations before raising duplicate uniqueness errors' do
      store.enqueue(
        job: submission_job(
          id: 'job-1',
          queue: 'billing',
          created_at:,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :queued
        ),
        now: created_at + 1
      )
      store.enqueue(job: submission_job(id: 'job-2', queue: 'shipping', created_at: created_at + 1), now: created_at + 2)
      reservation = store.reserve(queue: 'shipping', worker_id: 'worker-1', lease_duration: 2, now: created_at + 3)

      expect do
        store.enqueue(
          job: submission_job(
            id: 'job-3',
            queue: 'billing',
            created_at: created_at + 4,
            uniqueness_key: 'billing:account-42',
            uniqueness_scope: :active
          ),
          now: created_at + 6
        )
      end.to raise_error(Karya::DuplicateUniquenessKeyError, /billing:account-42/)

      expect(stored_job('job-2').state).to eq(:reserved)
      expect { store.release(reservation_token: reservation.token, now: created_at + 7) }.to raise_error(Karya::ExpiredReservationError)
      next_reservation = store.reserve(queue: 'shipping', worker_id: 'worker-2', lease_duration: 30, now: created_at + 8)
      expect(next_reservation.job_id).to eq('job-2')
    end

    it 'rejects duplicate idempotency keys' do
      original_job = store.enqueue(
        job: submission_job(
          id: 'job-1',
          queue: 'billing',
          created_at:,
          idempotency_key: 'submit-123'
        ),
        now: created_at + 1
      )

      expect do
        store.enqueue(
          job: submission_job(
            id: 'job-2',
            queue: 'billing',
            created_at: created_at + 1,
            idempotency_key: 'submit-123'
          ),
          now: created_at + 2
        )
      end.to raise_error(Karya::DuplicateIdempotencyKeyError, /submit-123/)

      expect(stored_job('job-1')).to eq(original_job)
      expect(store_state.jobs_by_id.keys).to eq(['job-1'])
    end

    it 'does not recover expired reservations before raising duplicate idempotency errors' do
      store.enqueue(
        job: submission_job(
          id: 'job-1',
          queue: 'billing',
          created_at:,
          idempotency_key: 'submit-123'
        ),
        now: created_at + 1
      )
      store.enqueue(job: submission_job(id: 'job-2', queue: 'shipping', created_at: created_at + 1), now: created_at + 2)
      reservation = store.reserve(queue: 'shipping', worker_id: 'worker-1', lease_duration: 2, now: created_at + 3)

      expect do
        store.enqueue(
          job: submission_job(
            id: 'job-3',
            queue: 'billing',
            created_at: created_at + 4,
            idempotency_key: 'submit-123'
          ),
          now: created_at + 6
        )
      end.to raise_error(Karya::DuplicateIdempotencyKeyError, /submit-123/)

      expect(stored_job('job-2').state).to eq(:reserved)
      expect { store.release(reservation_token: reservation.token, now: created_at + 7) }.to raise_error(Karya::ExpiredReservationError)
      next_reservation = store.reserve(queue: 'shipping', worker_id: 'worker-2', lease_duration: 30, now: created_at + 8)
      expect(next_reservation.job_id).to eq('job-2')
    end

    it 'rejects duplicate ids before checking uniqueness conflicts' do
      original_job = store.enqueue(
        job: submission_job(
          id: 'job-1',
          queue: 'billing',
          created_at:,
          uniqueness_key: 'key-a',
          uniqueness_scope: :active
        ),
        now: created_at + 1
      )

      expect do
        store.enqueue(
          job: submission_job(
            id: 'job-1',
            queue: 'billing',
            created_at: created_at + 1,
            uniqueness_key: 'key-b',
            uniqueness_scope: :active
          ),
          now: created_at + 2
        )
      end.to raise_error(Karya::DuplicateJobError, /job-1/)

      expect(stored_job('job-1')).to eq(original_job)
    end

    it 'accepts long idempotency and uniqueness keys with control and unicode characters' do
      composite_key = "#{'x' * 4096}\nsnowman-\u2603"

      queued_job = store.enqueue(
        job: submission_job(
          id: 'job-1',
          queue: 'billing',
          created_at:,
          idempotency_key: composite_key,
          uniqueness_key: composite_key,
          uniqueness_scope: :active
        ),
        now: created_at + 1
      )

      expect(queued_job.idempotency_key).to eq(composite_key)
      expect(queued_job.uniqueness_key).to eq(composite_key)
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
