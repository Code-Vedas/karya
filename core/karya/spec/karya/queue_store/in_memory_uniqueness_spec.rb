# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::InMemory do
  subject(:store) { described_class.new(token_generator: token_generator) }

  let(:token_sequence) { %w[lease-1 lease-2 lease-3 lease-4 lease-5].each }
  let(:token_generator) { -> { token_sequence.next } }
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }
  let(:retry_policy) { Karya::RetryPolicy.new(max_attempts: 3, base_delay: 5, multiplier: 2) }

  def stored_job(id)
    store.instance_variable_get(:@state).jobs_by_id.fetch(id)
  end

  def submission_job(id:, uniqueness_scope:, created_at:, uniqueness_key: 'billing:account-42')
    Karya::Job.new(
      id:,
      queue: 'billing',
      handler: 'billing_sync',
      uniqueness_key:,
      uniqueness_scope:,
      state: :submission,
      created_at:
    )
  end

  describe 'uniqueness blocking windows' do
    it 'allows a duplicate after the original succeeds for queued scope' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :queued, created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.complete_execution(reservation_token: reservation.token, now: created_at + 4)

      expect do
        store.enqueue(job: submission_job(id: 'job-2', uniqueness_scope: :queued, created_at: created_at + 4), now: created_at + 5)
      end.not_to raise_error
    end

    it 'blocks a duplicate while the original is running for active scope' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :active, created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      expect do
        store.enqueue(job: submission_job(id: 'job-2', uniqueness_scope: :active, created_at: created_at + 3), now: created_at + 4)
      end.to raise_error(Karya::DuplicateUniquenessKeyError, /billing:account-42/)
    end

    it 'allows a duplicate once a queued-scope job becomes reserved' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :queued, created_at:), now: created_at + 1)
      store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      expect do
        store.enqueue(job: submission_job(id: 'job-2', uniqueness_scope: :queued, created_at: created_at + 2), now: created_at + 3)
      end.not_to raise_error
    end

    it 'keeps blocking a duplicate once an active-scope job becomes reserved' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :active, created_at:), now: created_at + 1)
      store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      expect do
        store.enqueue(job: submission_job(id: 'job-2', uniqueness_scope: :active, created_at: created_at + 2), now: created_at + 3)
      end.to raise_error(Karya::DuplicateUniquenessKeyError, /billing:account-42/)
    end

    it 'blocks a duplicate while the original is retry_pending for queued scope' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :queued, created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        retry_policy: retry_policy,
        failure_classification: :error
      )

      expect do
        store.enqueue(job: submission_job(id: 'job-2', uniqueness_scope: :queued, created_at: created_at + 4), now: created_at + 5)
      end.to raise_error(Karya::DuplicateUniquenessKeyError, /billing:account-42/)
    end

    it 'allows a duplicate after the original fails terminally for active scope' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :active, created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        failure_classification: :error
      )

      expect do
        store.enqueue(job: submission_job(id: 'job-2', uniqueness_scope: :active, created_at: created_at + 4), now: created_at + 5)
      end.not_to raise_error
    end

    it 'blocks a duplicate until terminal recovery completes for until_terminal scope' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :until_terminal, created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 2, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.recover_in_flight(now: created_at + 6)

      expect do
        store.enqueue(
          job: submission_job(id: 'job-2', uniqueness_scope: :until_terminal, created_at: created_at + 6),
          now: created_at + 7
        )
      end.to raise_error(Karya::DuplicateUniquenessKeyError, /billing:account-42/)
    end

    it 'allows a duplicate after the original reaches a terminal state for until_terminal scope' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :until_terminal, created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.complete_execution(reservation_token: reservation.token, now: created_at + 4)

      expect do
        store.enqueue(
          job: submission_job(id: 'job-2', uniqueness_scope: :until_terminal, created_at: created_at + 4),
          now: created_at + 5
        )
      end.not_to raise_error
    end

    it 'allows a duplicate when uniqueness_key is present without uniqueness_scope' do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-1',
          queue: 'billing',
          handler: 'billing_sync',
          uniqueness_key: 'billing:account-42',
          state: :submission,
          created_at:
        ),
        now: created_at + 1
      )

      expect do
        store.enqueue(
          job: Karya::Job.new(
            id: 'job-2',
            queue: 'billing',
            handler: 'billing_sync',
            uniqueness_key: 'billing:account-42',
            state: :submission,
            created_at: created_at + 1
          ),
          now: created_at + 2
        )
      end.not_to raise_error
    end

    it 'ignores non-blocking terminal jobs when checking uniqueness conflicts' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :active, created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.complete_execution(reservation_token: reservation.token, now: created_at + 4)

      expect do
        store.enqueue(
          job: submission_job(id: 'job-2', uniqueness_scope: :active, created_at: created_at + 4),
          now: created_at + 5
        )
      end.not_to raise_error
    end

    it 'ignores jobs with a uniqueness key but no scope when checking uniqueness conflicts' do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-1',
          queue: 'billing',
          handler: 'billing_sync',
          uniqueness_key: 'billing:account-42',
          state: :submission,
          created_at:
        ),
        now: created_at + 1
      )

      expect do
        store.enqueue(
          job: submission_job(id: 'job-2', uniqueness_scope: :active, created_at: created_at + 1),
          now: created_at + 2
        )
      end.not_to raise_error
    end

    it 'allows jobs without uniqueness metadata to enqueue freely' do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-1',
          queue: 'billing',
          handler: 'billing_sync',
          state: :submission,
          created_at:
        ),
        now: created_at + 1
      )

      expect do
        store.enqueue(
          job: Karya::Job.new(
            id: 'job-2',
            queue: 'billing',
            handler: 'billing_sync',
            state: :submission,
            created_at: created_at + 1
          ),
          now: created_at + 2
        )
      end.not_to raise_error
    end

    it 'ignores other jobs with different uniqueness keys' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :active, created_at:, uniqueness_key: 'billing:account-1'), now: created_at + 1)

      expect do
        store.enqueue(job: submission_job(id: 'job-2', uniqueness_scope: :active, created_at: created_at + 1), now: created_at + 2)
      end.not_to raise_error
    end

    it 'rejects duplicate idempotency keys even after the original succeeds' do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-1',
          queue: 'billing',
          handler: 'billing_sync',
          idempotency_key: 'submit-123',
          state: :submission,
          created_at:
        ),
        now: created_at + 1
      )
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.complete_execution(reservation_token: reservation.token, now: created_at + 4)

      expect do
        store.enqueue(
          job: Karya::Job.new(
            id: 'job-2',
            queue: 'billing',
            handler: 'billing_sync',
            idempotency_key: 'submit-123',
            state: :submission,
            created_at: created_at + 4
          ),
          now: created_at + 5
        )
      end.to raise_error(Karya::DuplicateIdempotencyKeyError, /submit-123/)
    end

    it 'ignores other jobs with different idempotency keys' do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-1',
          queue: 'billing',
          handler: 'billing_sync',
          idempotency_key: 'submit-001',
          state: :submission,
          created_at:
        ),
        now: created_at + 1
      )

      expect do
        store.enqueue(
          job: Karya::Job.new(
            id: 'job-2',
            queue: 'billing',
            handler: 'billing_sync',
            idempotency_key: 'submit-002',
            state: :submission,
            created_at: created_at + 1
          ),
          now: created_at + 2
        )
      end.not_to raise_error
    end

    it 'fails a queued-scope reentry when a later duplicate is already queued' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :queued, created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.enqueue(job: submission_job(id: 'job-2', uniqueness_scope: :queued, created_at: created_at + 2), now: created_at + 3)

      released_job = store.release(reservation_token: reservation.token, now: created_at + 4)

      expect(released_job.state).to eq(:cancelled)
      expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 5)&.job_id).to eq('job-2')
    end

    it 'fails retry reentry when a duplicate is already queued' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :queued, created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.enqueue(job: submission_job(id: 'job-2', uniqueness_scope: :queued, created_at: created_at + 3), now: created_at + 4)

      failed_job = store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 5,
        retry_policy: retry_policy,
        failure_classification: :error
      )

      expect(failed_job.state).to eq(:cancelled)
    end

    it 'fails expired execution recovery reentry when a duplicate is already queued' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :queued, created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 5, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.enqueue(job: submission_job(id: 'job-2', uniqueness_scope: :queued, created_at: created_at + 3), now: created_at + 4)

      report = store.recover_in_flight(now: created_at + 8)
      recovered_job = report.recovered_running_jobs.find { |job| job.id == 'job-1' }

      expect(recovered_job&.state).to eq(:cancelled)
    end

    it 'fails queued reentry when a conflicting reservation has already expired at the reentry time' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :queued, created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      conflicting_job = submission_job(id: 'job-2', uniqueness_scope: :queued, created_at: created_at + 2)
      store.enqueue(job: conflicting_job, now: created_at + 3)
      conflicting_reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 2, now: created_at + 4)

      released_job = store.release(reservation_token: reservation.token, now: created_at + 7)

      expect(released_job.state).to eq(:cancelled)
      expect { store.release(reservation_token: conflicting_reservation.token, now: created_at + 8) }
        .to raise_error(Karya::ExpiredReservationError)
      next_reservation = store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 30, now: created_at + 9)
      expect(next_reservation&.job_id).to eq('job-2')
    end

    it 'blocks an active-scope enqueue against an existing reserved queued-scope job' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :queued, created_at:), now: created_at + 1)
      store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      expect do
        store.enqueue(job: submission_job(id: 'job-2', uniqueness_scope: :active, created_at: created_at + 2), now: created_at + 3)
      end.to raise_error(Karya::DuplicateUniquenessKeyError, /billing:account-42/)
    end

    it 'releases until-terminal uniqueness after a non-retriable failure' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :until_terminal, created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        failure_classification: :error
      )

      expect do
        store.enqueue(job: submission_job(id: 'job-2', uniqueness_scope: :until_terminal, created_at: created_at + 4), now: created_at + 5)
      end.not_to raise_error
    end

    it 'releases until-terminal uniqueness after expiration to failed' do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-1',
          queue: 'billing',
          handler: 'billing_sync',
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :until_terminal,
          expires_at: created_at + 3,
          state: :submission,
          created_at:
        ),
        now: created_at + 1
      )

      store.expire_jobs(now: created_at + 4)

      expect do
        store.enqueue(job: submission_job(id: 'job-2', uniqueness_scope: :until_terminal, created_at: created_at + 4), now: created_at + 5)
      end.not_to raise_error
    end

    it 'expires a reserved job on execution start and releases active uniqueness' do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-1',
          queue: 'billing',
          handler: 'billing_sync',
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :active,
          expires_at: created_at + 4,
          state: :submission,
          created_at:
        ),
        now: created_at + 1
      )
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      expired_job = store.start_execution(reservation_token: reservation.token, now: created_at + 5)

      expect(expired_job.id).to eq('job-1')
      expect(expired_job.state).to eq(:failed)
      expect(stored_job('job-1').state).to eq(:failed)
      expect(stored_job('job-1').failure_classification).to eq(:expired)
      expect do
        store.enqueue(job: submission_job(id: 'job-2', uniqueness_scope: :active, created_at: created_at + 5), now: created_at + 6)
      end.not_to raise_error
      expect { store.release(reservation_token: reservation.token, now: created_at + 6) }.to raise_error(Karya::ExpiredReservationError)
    end

    it 'can build a failed reentry conflict job when the current state allows failure' do
      running_job = Karya::Job.new(
        id: 'job-1',
        queue: 'billing',
        handler: 'billing_sync',
        uniqueness_key: 'billing:account-42',
        uniqueness_scope: :active,
        state: :running,
        attempt: 1,
        created_at:,
        updated_at: created_at + 1
      )

      conflict_job = store.send(:reentry_conflict_job, running_job)

      expect(conflict_job.state).to eq(:failed)
      expect(conflict_job.failure_classification).to eq(:error)
    end

    it 'returns the original job for uniqueness evaluation when no effective-state time is provided' do
      queued_job = submission_job(id: 'job-1', uniqueness_scope: :queued, created_at:).transition_to(:queued, updated_at: created_at + 1)

      expect(store.send(:effective_uniqueness_job, queued_job, nil)).to eq(queued_job)
    end
  end
end
