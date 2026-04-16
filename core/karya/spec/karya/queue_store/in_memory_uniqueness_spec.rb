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

    it 'drops stale uniqueness mappings before enqueueing a replacement job' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :active, created_at:), now: created_at + 1)
      store_state = store.instance_variable_get(:@state)
      store_state.uniqueness_job_id_by_key['billing:account-42'] = 'missing-job'

      expect do
        store.enqueue(
          job: submission_job(id: 'job-2', uniqueness_scope: :active, created_at: created_at + 1),
          now: created_at + 2
        )
      end.not_to raise_error

      expect(store_state.uniqueness_job_id_by_key).to eq('billing:account-42' => 'job-2')
    end

    it 'clears stale mappings for existing non-blocking terminal jobs' do
      store.enqueue(job: submission_job(id: 'job-1', uniqueness_scope: :active, created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.complete_execution(reservation_token: reservation.token, now: created_at + 4)

      store_state = store.instance_variable_get(:@state)
      store_state.register_uniqueness_job('billing:account-42', 'job-1')

      expect do
        store.enqueue(
          job: submission_job(id: 'job-2', uniqueness_scope: :active, created_at: created_at + 4),
          now: created_at + 5
        )
      end.not_to raise_error

      expect(store_state.uniqueness_job_id_by_key).to eq('billing:account-42' => 'job-2')
    end

    it 'clears stale mappings for jobs with a uniqueness key but no scope' do
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

      store_state = store.instance_variable_get(:@state)
      store_state.register_uniqueness_job('billing:account-42', 'job-1')

      expect do
        store.enqueue(
          job: submission_job(id: 'job-2', uniqueness_scope: :active, created_at: created_at + 1),
          now: created_at + 2
        )
      end.not_to raise_error

      expect(store_state.uniqueness_job_id_by_key).to eq('billing:account-42' => 'job-2')
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
  end
end
