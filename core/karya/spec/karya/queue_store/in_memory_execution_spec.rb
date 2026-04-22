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
  let(:retry_policy) { Karya::RetryPolicy.new(max_attempts: 3, base_delay: 5, multiplier: 2, max_delay: 12) }

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

    it 'fails an expired reserved job before execution starts' do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-1',
          queue: 'billing',
          handler: 'billing_sync',
          state: :submission,
          created_at: created_at,
          expires_at: created_at + 4
        ),
        now: created_at + 1
      )
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      failed_job = store.start_execution(reservation_token: reservation.token, now: created_at + 5)

      expect(failed_job.state).to eq(:failed)
      expect(failed_job.failure_classification).to eq(:expired)
      expect(store_state.reservations_by_token).to eq({})
      expect(store_state.executions_by_token).to eq({})
      expect(stored_job('job-1').state).to eq(:failed)
    end

    it 'does not activate execution when the running-job transition cannot be persisted' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store_state.jobs_by_id.delete('job-1')

      expect do
        store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      end.to raise_error(KeyError)

      expect(store_state.executions_by_token).to eq({})
      expect(store_state.reservations_by_token.keys).to eq([reservation.token])
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

    it 'rejects expired execution leases and requeues the running job' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 2.5)

      expect do
        store.complete_execution(reservation_token: reservation.token, now: created_at + 5)
      end.to raise_error(Karya::ExpiredReservationError, /#{reservation.token}/)

      expect(stored_job('job-1').state).to eq(:queued)
      expect(store_state.executions_by_token).to eq({})
    end
  end

  describe '#fail_execution' do
    it 'finalizes a running job as failed and preserves the incremented attempt count' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      failed_job = store.fail_execution(reservation_token: reservation.token, now: created_at + 4, failure_classification: :error)

      expect(failed_job.state).to eq(:failed)
      expect(failed_job.attempt).to eq(1)
      expect(failed_job.failure_classification).to eq(:error)
      expect(stored_job('job-1').state).to eq(:failed)
    end

    it 'rejects tokens that never entered execution' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      expect do
        store.fail_execution(reservation_token: reservation.token, now: created_at + 3, failure_classification: :error)
      end.to raise_error(Karya::UnknownReservationError, /was not found/)
    end

    it 'rejects invalid retry policy objects' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      expect do
        store.fail_execution(
          reservation_token: reservation.token,
          now: created_at + 4,
          retry_policy: 'not-a-policy',
          failure_classification: :error
        )
      end.to raise_error(Karya::InvalidQueueStoreOperationError, 'retry_policy must be a Karya::RetryPolicy')
    end

    it 'rejects invalid failure classifications' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      expect do
        store.fail_execution(
          reservation_token: reservation.token,
          now: created_at + 4,
          failure_classification: :boom
        )
      end.to raise_error(
        Karya::InvalidQueueStoreOperationError,
        'failure_classification must be one of :error, :timeout, or :expired'
      )
    end

    it 'rejects invalid failure classification types' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      expect do
        store.fail_execution(
          reservation_token: reservation.token,
          now: created_at + 4,
          failure_classification: 123
        )
      end.to raise_error(
        Karya::InvalidQueueStoreOperationError,
        'failure_classification must be one of :error, :timeout, or :expired'
      )
    end

    it 'requires failure classification when finalizing a failed execution' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      expect do
        store.fail_execution(
          reservation_token: reservation.token,
          now: created_at + 4,
          failure_classification: nil
        )
      end.to raise_error(
        Karya::InvalidQueueStoreOperationError,
        'failure_classification must be one of :error, :timeout, or :expired'
      )
    end

    it 'accepts string expired classification and keeps it terminal' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      failed_job = store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        retry_policy: retry_policy,
        failure_classification: 'expired'
      )

      expect(failed_job.state).to eq(:failed)
      expect(failed_job.failure_classification).to eq(:expired)
      expect(store_state.retry_pending_job_ids).to eq([])
    end

    it 'rejects expired execution leases and requeues the running job' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 2.5)

      expect do
        store.fail_execution(reservation_token: reservation.token, now: created_at + 5, failure_classification: :error)
      end.to raise_error(Karya::ExpiredReservationError, /#{reservation.token}/)

      expect(stored_job('job-1').state).to eq(:queued)
      expect(store_state.executions_by_token).to eq({})
    end

    it 'transitions a running job to retry_pending when retry policy allows another attempt' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      retried_job = store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        retry_policy: retry_policy,
        failure_classification: :timeout
      )

      expect(retried_job.state).to eq(:retry_pending)
      expect(retried_job.attempt).to eq(1)
      expect(retried_job.retry_policy).to eq(retry_policy)
      expect(retried_job.next_retry_at).to eq(created_at + 9)
      expect(retried_job.failure_classification).to eq(:timeout)
      expect(stored_job('job-1').state).to eq(:retry_pending)
      expect(store_state.retry_pending_job_ids).to eq(['job-1'])
    end

    it 'uses deterministic jitter to spread retry scheduling for different jobs' do
      jitter_policy = Karya::RetryPolicy.new(max_attempts: 3, base_delay: 5, multiplier: 2, jitter_strategy: :equal)
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 0.5), now: created_at + 1.5)

      first_reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: first_reservation.token, now: created_at + 3)
      first_retry = store.fail_execution(
        reservation_token: first_reservation.token,
        now: created_at + 4,
        retry_policy: jitter_policy,
        failure_classification: :error
      )

      second_reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 5)
      store.start_execution(reservation_token: second_reservation.token, now: created_at + 6)
      second_retry = store.fail_execution(
        reservation_token: second_reservation.token,
        now: created_at + 7,
        retry_policy: jitter_policy,
        failure_classification: :error
      )

      expect(first_retry.state).to eq(:retry_pending)
      expect(second_retry.state).to eq(:retry_pending)
      expect(first_retry.next_retry_at).not_to eq(second_retry.next_retry_at)
      expect(first_retry.next_retry_at).to be >= created_at + 6.5
      expect(first_retry.next_retry_at).to be <= created_at + 9
      expect(second_retry.next_retry_at).to be >= created_at + 9.5
      expect(second_retry.next_retry_at).to be <= created_at + 12
    end

    it 'dead-letters a failed job when max_attempts is exhausted' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        retry_policy: retry_policy,
        failure_classification: :error
      )

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 9)
      running_job = store.start_execution(reservation_token: reservation.token, now: created_at + 10)
      expect(running_job.attempt).to eq(2)
      store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 11,
        retry_policy: retry_policy,
        failure_classification: :error
      )

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 21)
      running_job = store.start_execution(reservation_token: reservation.token, now: created_at + 22)
      expect(running_job.attempt).to eq(3)

      failed_job = store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 23,
        retry_policy: retry_policy,
        failure_classification: :error
      )

      expect(failed_job.state).to eq(:dead_letter)
      expect(failed_job.next_retry_at).to be_nil
      expect(failed_job.failure_classification).to eq(:error)
      expect(failed_job.dead_letter_reason).to eq('retry-policy-exhausted')
      expect(store_state.retry_pending_job_ids).to eq([])
    end

    it 'dead-letters a failed job when retry policy escalates the failure classification' do
      escalation_policy = Karya::RetryPolicy.new(max_attempts: 3, base_delay: 5, multiplier: 2, escalate_on: [:timeout])
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      failed_job = store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        retry_policy: escalation_policy,
        failure_classification: :timeout
      )

      expect(failed_job.state).to eq(:dead_letter)
      expect(failed_job.next_retry_at).to be_nil
      expect(failed_job.failure_classification).to eq(:timeout)
      expect(failed_job.dead_letter_reason).to eq('retry-policy-escalated')
      expect(store_state.retry_pending_job_ids).to eq([])
    end

    it 'does not reserve retry_pending jobs before they are due' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        retry_policy: retry_policy,
        failure_classification: :error
      )

      expect(store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 8)).to be_nil
      expect(stored_job('job-1').state).to eq(:retry_pending)
    end

    it 'promotes due retry_pending jobs during reserve maintenance' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        retry_policy: retry_policy,
        failure_classification: :error
      )

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 9)

      expect(reservation.job_id).to eq('job-1')
      expect(stored_job('job-1').state).to eq(:reserved)
      expect(store_state.retry_pending_job_ids).to eq([])
      expect(stored_job('job-1').failure_classification).to be_nil
    end
  end

  describe '#expire_jobs' do
    it 'fails queued jobs whose expires_at has passed' do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-1',
          queue: 'billing',
          handler: 'billing_sync',
          state: :submission,
          created_at: created_at,
          expires_at: created_at + 2
        ),
        now: created_at + 1
      )

      expired_jobs = store.expire_jobs(now: created_at + 2)

      expect(expired_jobs.map(&:id)).to eq(['job-1'])
      expect(stored_job('job-1').state).to eq(:failed)
      expect(stored_job('job-1').failure_classification).to eq(:expired)
      expect(store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)).to be_nil
    end

    it 'fails retry_pending jobs whose expires_at passes before the retry is due' do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-1',
          queue: 'billing',
          handler: 'billing_sync',
          state: :submission,
          created_at: created_at,
          expires_at: created_at + 6
        ),
        now: created_at + 1
      )
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        retry_policy: retry_policy,
        failure_classification: :error
      )

      expired_jobs = store.expire_jobs(now: created_at + 6)

      expect(expired_jobs.map(&:id)).to eq(['job-1'])
      expect(stored_job('job-1').state).to eq(:failed)
      expect(stored_job('job-1').failure_classification).to eq(:expired)
      expect(store_state.retry_pending_job_ids).to eq([])
    end
  end
end
