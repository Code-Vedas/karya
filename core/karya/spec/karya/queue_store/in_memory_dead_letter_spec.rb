# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::InMemory do
  subject(:store) { described_class.new(token_generator:) }

  let(:token_sequence) { %w[lease-1 lease-2 lease-3 lease-4 lease-5].each }
  let(:token_generator) { -> { token_sequence.next } }
  let(:created_at) { Time.utc(2026, 4, 21, 12, 0, 0) }

  def submission_job(id:, queue: 'billing', handler: 'billing_sync', uniqueness_key: nil, uniqueness_scope: nil)
    Karya::Job.new(
      id:,
      queue:,
      handler:,
      state: :submission,
      created_at:,
      uniqueness_key:,
      uniqueness_scope:
    )
  end

  def stored_job(id)
    store_state.jobs_by_id.fetch(id)
  end

  def store_state
    store.instance_variable_get(:@state)
  end

  def enqueue_job(id, **attributes)
    store.enqueue(job: submission_job(id:, **attributes), now: created_at + 1)
  end

  def dead_letter_job(id, reason: 'manual')
    store.dead_letter_jobs(job_ids: [id], now: created_at + 2, reason:).changed_jobs.fetch(0)
  end

  describe '#fail_execution' do
    it 'dead-letters retry-policy escalation caused by exhaustion' do
      enqueue_job('job-1')
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      dead_lettered_job = store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        failure_classification: :error,
        retry_policy: Karya::RetryPolicy.new(max_attempts: 1, base_delay: 1, multiplier: 1)
      )

      expect(dead_lettered_job.state).to eq(:dead_letter)
      expect(dead_lettered_job.dead_letter_reason).to eq('retry-policy-exhausted')
      expect(dead_lettered_job.dead_lettered_at).to eq(created_at + 4)
      expect(dead_lettered_job.dead_letter_source_state).to eq(:failed)
      expect(store_state.executions_by_token).to eq({})
    end

    it 'keeps expired failures as failed instead of dead-lettering' do
      enqueue_job('job-1')
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      failed_job = store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        failure_classification: :expired,
        retry_policy: Karya::RetryPolicy.new(max_attempts: 1, base_delay: 1, multiplier: 1)
      )

      expect(failed_job.state).to eq(:failed)
      expect(failed_job.dead_letter_reason).to be_nil
    end
  end

  describe 'operator dead-letter recovery' do
    it 'isolates queued work and skips it during reservation until replayed' do
      enqueue_job('job-1')
      enqueue_job('job-2', queue: 'shipping')

      report = store.dead_letter_jobs(job_ids: ['job-1'], now: created_at + 2, reason: 'operator-isolated')

      expect(report.action).to eq(:dead_letter_jobs)
      expect(report.changed_jobs.fetch(0).state).to eq(:dead_letter)
      expect(store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)).to be_nil
      expect(store.reserve(queue: 'shipping', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3).job_id).to eq('job-2')

      replay_report = store.replay_dead_letter_jobs(job_ids: ['job-1'], now: created_at + 4)

      expect(replay_report.changed_jobs.fetch(0).state).to eq(:queued)
      expect(replay_report.changed_jobs.fetch(0).dead_letter_reason).to be_nil
      expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 5).job_id).to eq('job-1')
    end

    it 'tombstones active reservations when isolating reserved work' do
      enqueue_job('job-1')
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      store.dead_letter_jobs(job_ids: ['job-1'], now: created_at + 3, reason: 'poison')

      expect(store_state.expired_reservation_tokens).to include(reservation.token => true)
      expect do
        store.start_execution(reservation_token: reservation.token, now: created_at + 4)
      end.to raise_error(Karya::ExpiredReservationError)
    end

    it 'tombstones active executions when isolating running work' do
      enqueue_job('job-1')
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      store.dead_letter_jobs(job_ids: ['job-1'], now: created_at + 4, reason: 'poison')

      expect(store_state.expired_reservation_tokens).to include(reservation.token => true)
      expect do
        store.complete_execution(reservation_token: reservation.token, now: created_at + 5)
      end.to raise_error(Karya::ExpiredReservationError)
    end

    it 'removes retry-pending indexes when isolating retry-pending work' do
      enqueue_job('job-1')
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        failure_classification: :error,
        retry_policy: Karya::RetryPolicy.new(max_attempts: 3, base_delay: 10, multiplier: 1)
      )

      store.dead_letter_jobs(job_ids: ['job-1'], now: created_at + 5, reason: 'operator-isolated')

      expect(store_state.retry_pending_job_ids).to eq([])
      expect(stored_job('job-1').state).to eq(:dead_letter)
    end

    it 'moves dead-letter work to retry_pending for controlled retry' do
      enqueue_job('job-1')
      dead_letter_job('job-1')

      retry_report = store.retry_dead_letter_jobs(
        job_ids: ['job-1'],
        now: created_at + 3,
        next_retry_at: created_at + 10
      )

      retried_job = retry_report.changed_jobs.fetch(0)
      expect(retried_job.state).to eq(:retry_pending)
      expect(retried_job.next_retry_at).to eq(created_at + 10)
      expect(retried_job.dead_letter_reason).to be_nil
      expect(store_state.retry_pending_job_ids).to eq(['job-1'])
    end

    it 'discards dead-letter work by cancelling it' do
      enqueue_job('job-1')
      dead_letter_job('job-1')

      discard_report = store.discard_dead_letter_jobs(job_ids: ['job-1'], now: created_at + 3)

      expect(discard_report.changed_jobs.fetch(0).state).to eq(:cancelled)
      expect(stored_job('job-1').dead_letter_reason).to be_nil
    end

    it 'skips replay when uniqueness would conflict' do
      enqueue_job('job-1', uniqueness_key: 'account-1', uniqueness_scope: :queued)
      dead_letter_job('job-1')
      enqueue_job('job-2', uniqueness_key: 'account-1', uniqueness_scope: :queued)

      replay_report = store.replay_dead_letter_jobs(job_ids: ['job-1'], now: created_at + 3)

      expect(replay_report.changed_jobs).to eq([])
      expect(replay_report.skipped_jobs).to eq([{ job_id: 'job-1', reason: :uniqueness_conflict, state: :dead_letter }])
    end

    it 'reports duplicate requests and ineligible recovery states' do
      enqueue_job('job-1')
      enqueue_job('job-2')

      duplicate_report = store.dead_letter_jobs(job_ids: %w[job-1 job-1], now: created_at + 2, reason: 'manual')
      replay_report = store.replay_dead_letter_jobs(job_ids: ['job-2'], now: created_at + 3)
      discard_report = store.discard_dead_letter_jobs(job_ids: ['job-2'], now: created_at + 3)

      expect(duplicate_report.skipped_jobs).to eq([{ job_id: 'job-1', reason: :duplicate_request, state: nil }])
      expect(replay_report.skipped_jobs).to eq([{ job_id: 'job-2', reason: :ineligible_state, state: :queued }])
      expect(discard_report.skipped_jobs).to eq([{ job_id: 'job-2', reason: :ineligible_state, state: :queued }])
    end

    it 'reports invalid and ineligible isolation requests' do
      enqueue_job('job-1')
      store.cancel_jobs(job_ids: ['job-1'], now: created_at + 2)

      report = store.dead_letter_jobs(job_ids: ['job-1'], now: created_at + 3, reason: 'manual')

      expect(report.skipped_jobs).to eq([{ job_id: 'job-1', reason: :ineligible_state, state: :cancelled }])
      expect do
        store.dead_letter_jobs(job_ids: ['job-2'], now: created_at + 3, reason: 'a' * 1025)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, 'dead_letter_reason must be at most 1024 characters')
      expect do
        store.dead_letter_jobs(job_ids: ['job-2'], now: created_at + 3, reason: '')
      end.to raise_error(Karya::InvalidQueueStoreOperationError, 'dead_letter_reason must be present')
      expect do
        store.dead_letter_jobs(job_ids: ['job-2'], now: created_at + 3, reason: " \t ")
      end.to raise_error(Karya::InvalidQueueStoreOperationError, 'dead_letter_reason must be present')
      expect do
        store.dead_letter_jobs(job_ids: ['job-2'], now: created_at + 3, reason: :manual)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, 'dead_letter_reason must be a String')
    end

    it 'reports missing jobs across dead-letter recovery actions' do
      expect(store.dead_letter_jobs(job_ids: ['missing'], now: created_at + 1, reason: 'manual').skipped_jobs)
        .to eq([{ job_id: 'missing', reason: :not_found, state: nil }])
      expect(store.replay_dead_letter_jobs(job_ids: ['missing'], now: created_at + 1).skipped_jobs)
        .to eq([{ job_id: 'missing', reason: :not_found, state: nil }])
      expect(store.retry_dead_letter_jobs(job_ids: ['missing'], now: created_at + 1, next_retry_at: created_at + 2).skipped_jobs)
        .to eq([{ job_id: 'missing', reason: :not_found, state: nil }])
      expect(store.discard_dead_letter_jobs(job_ids: ['missing'], now: created_at + 1).skipped_jobs)
        .to eq([{ job_id: 'missing', reason: :not_found, state: nil }])
    end

    it 'isolates failed work without scheduling cleanup' do
      enqueue_job('job-1')
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(reservation_token: reservation.token, now: created_at + 4, failure_classification: :error)

      report = store.dead_letter_jobs(job_ids: ['job-1'], now: created_at + 5, reason: 'manual')

      expect(report.changed_jobs.fetch(0).state).to eq(:dead_letter)
    end
  end

  describe '#dead_letter_snapshot' do
    it 'returns a fully frozen dead-letter snapshot' do
      enqueue_job('job-1')
      dead_letter_job('job-1', reason: 'operator-isolated')
      enqueue_job('job-2')

      snapshot = store.dead_letter_snapshot(now: created_at + 3)
      entry = snapshot.fetch(:dead_letters).fetch(0)

      expect(snapshot).to include(captured_at: created_at + 3)
      expect(entry).to include(
        job_id: 'job-1',
        state: :dead_letter,
        dead_letter_reason: 'operator-isolated',
        available_actions: %i[replay retry discard]
      )
      expect(snapshot).to be_frozen
      expect(snapshot.fetch(:dead_letters)).to be_frozen
      expect(entry).to be_frozen
    end

    it 'does not promote due retry-pending jobs while inspecting dead letters' do
      enqueue_job('job-1')
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        failure_classification: :error,
        retry_policy: Karya::RetryPolicy.new(max_attempts: 3, base_delay: 1, multiplier: 1)
      )

      store.dead_letter_snapshot(now: created_at + 10)

      expect(stored_job('job-1').state).to eq(:retry_pending)
      expect(store_state.retry_pending_job_ids).to eq(['job-1'])
    end
  end
end
