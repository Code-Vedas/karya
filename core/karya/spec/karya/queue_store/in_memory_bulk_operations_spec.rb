# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::InMemory do
  subject(:store) { described_class.new(token_generator:) }

  let(:token_sequence) { %w[lease-1 lease-2 lease-3 lease-4 lease-5 lease-6].each }
  let(:token_generator) { -> { token_sequence.next } }
  let(:created_at) { Time.utc(2026, 4, 1, 12, 0, 0) }

  def submission_job(id:, created_at:, queue: 'billing', handler: 'billing_sync', idempotency_key: nil, uniqueness_key: nil, uniqueness_scope: nil)
    Karya::Job.new(
      id:,
      queue:,
      handler:,
      state: :submission,
      created_at:,
      idempotency_key:,
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

  def custom_state_job(id:, state:, created_at:)
    lifecycle = Karya::JobLifecycle::StateManager.new
    Karya::JobLifecycle::Extension.register_state(:paused, state_manager: lifecycle)
    Karya::JobLifecycle::Extension.register_transition(from: :paused, to: :cancelled, state_manager: lifecycle)
    Karya::Job.new(id:, queue: 'billing', handler: 'billing_sync', state:, created_at:, lifecycle:)
  end

  describe '#enqueue_many' do
    it 'atomically enqueues all jobs and returns a frozen bulk report' do
      report = store.enqueue_many(
        jobs: [
          submission_job(id: 'job-1', created_at:),
          submission_job(id: 'job-2', queue: 'shipping', created_at:)
        ],
        now: created_at + 1
      )

      expect(report).to be_a(Karya::QueueStore::BulkMutationReport)
      expect(report.action).to eq(:enqueue_many)
      expect(report.requested_count).to eq(2)
      expect(report.requested_job_ids).to eq(%w[job-1 job-2])
      expect(report.changed_jobs.map(&:state)).to eq(%i[queued queued])
      expect(report.skipped_jobs).to eq([])
      expect(report).to be_frozen
      expect(report.changed_jobs).to be_frozen
      expect(store_state.queued_job_ids_by_queue.fetch('billing')).to eq(['job-1'])
      expect(store_state.queued_job_ids_by_queue.fetch('shipping')).to eq(['job-2'])
    end

    it 'rejects an in-batch duplicate without partial writes' do
      jobs = [
        submission_job(id: 'job-1', created_at:),
        submission_job(id: 'job-2', created_at:, idempotency_key: 'same-key'),
        submission_job(id: 'job-3', created_at:, idempotency_key: 'same-key')
      ]

      expect do
        store.enqueue_many(jobs:, now: created_at + 1)
      end.to raise_error(Karya::DuplicateIdempotencyKeyError, /same-key/)

      expect(store_state.jobs_by_id).to eq({})
      expect(store_state.queued_job_ids_by_queue).to eq({})
    end

    it 'rejects in-batch duplicate job ids before other conflicts' do
      jobs = [
        submission_job(id: 'job-1', created_at:, idempotency_key: 'same-key'),
        submission_job(id: 'job-1', created_at:, idempotency_key: 'same-key')
      ]

      expect do
        store.enqueue_many(jobs:, now: created_at + 1)
      end.to raise_error(Karya::DuplicateJobError, /job-1/)

      expect(store_state.jobs_by_id).to eq({})
    end

    it 'rejects in-batch duplicate uniqueness keys without partial writes' do
      jobs = [
        submission_job(id: 'job-1', created_at:, uniqueness_key: 'account-1', uniqueness_scope: :queued),
        submission_job(id: 'job-2', created_at:, uniqueness_key: 'account-1', uniqueness_scope: :queued)
      ]

      expect do
        store.enqueue_many(jobs:, now: created_at + 1)
      end.to raise_error(Karya::DuplicateUniquenessKeyError, /account-1/)

      expect(store_state.jobs_by_id).to eq({})
    end

    it 'rejects an existing uniqueness conflict without partial writes' do
      store.enqueue(
        job: submission_job(id: 'job-1', created_at:, uniqueness_key: 'account-1', uniqueness_scope: :queued),
        now: created_at + 1
      )

      expect do
        store.enqueue_many(
          jobs: [
            submission_job(id: 'job-2', created_at:, uniqueness_key: 'account-1', uniqueness_scope: :queued),
            submission_job(id: 'job-3', created_at:)
          ],
          now: created_at + 2
        )
      end.to raise_error(Karya::DuplicateUniquenessKeyError, /account-1/)

      expect(store_state.jobs_by_id.keys).to eq(['job-1'])
      expect(store_state.queued_job_ids_by_queue.fetch('billing')).to eq(['job-1'])
    end

    it 'validates batch inputs before writing' do
      queued_job = submission_job(id: 'job-1', created_at:).transition_to(:queued, updated_at: created_at + 1)

      expect { store.enqueue_many(jobs: 'job-1', now: created_at + 2) }.to raise_error(Karya::InvalidEnqueueError, /jobs/)
      expect { store.enqueue_many(jobs: ['job-1'], now: created_at + 2) }.to raise_error(Karya::InvalidEnqueueError, /Karya::Job/)
      expect { store.enqueue_many(jobs: [queued_job], now: created_at + 2) }.to raise_error(Karya::InvalidEnqueueError, /submission/)
      expect(store_state.jobs_by_id).to eq({})
    end

    it 'accepts non-conflicting in-batch uniqueness keys' do
      report = store.enqueue_many(
        jobs: [
          submission_job(id: 'job-1', created_at:, uniqueness_key: 'account-1', uniqueness_scope: :queued),
          submission_job(id: 'job-2', created_at:, uniqueness_key: 'account-2', uniqueness_scope: :queued)
        ],
        now: created_at + 1
      )

      expect(report.changed_jobs.map(&:id)).to eq(%w[job-1 job-2])
    end
  end

  describe '#retry_jobs' do
    it 'requeues failed and retry-pending jobs and reports ineligible jobs' do
      failed_job = store.enqueue(job: submission_job(id: 'job-failed', created_at:), now: created_at + 1)
                        .transition_to(:reserved, updated_at: created_at + 2)
                        .transition_to(:running, updated_at: created_at + 3, attempt: 1)
                        .transition_to(:failed, updated_at: created_at + 4, failure_classification: :error)
      retry_job = store.enqueue(job: submission_job(id: 'job-retry', created_at:), now: created_at + 5)
                       .transition_to(:reserved, updated_at: created_at + 6)
                       .transition_to(:running, updated_at: created_at + 7, attempt: 1)
                       .transition_to(:failed, updated_at: created_at + 8, failure_classification: :error)
                       .transition_to(:retry_pending, updated_at: created_at + 9, next_retry_at: created_at + 100)
      succeeded_job = store.enqueue(job: submission_job(id: 'job-done', created_at:), now: created_at + 10)
                           .transition_to(:reserved, updated_at: created_at + 11)
                           .transition_to(:running, updated_at: created_at + 12, attempt: 1)
                           .transition_to(:succeeded, updated_at: created_at + 13)

      store_state.jobs_by_id['job-failed'] = failed_job
      store_state.jobs_by_id['job-retry'] = retry_job
      store_state.jobs_by_id['job-done'] = succeeded_job
      store_state.queued_job_ids_by_queue.clear
      store_state.register_retry_pending('job-retry')

      report = store.retry_jobs(job_ids: %w[job-failed job-retry job-done missing], now: created_at + 20)

      expect(report.changed_jobs.map(&:id)).to eq(%w[job-failed job-retry])
      expect(report.changed_jobs.map(&:state)).to eq(%i[queued queued])
      expect(report.skipped_jobs).to contain_exactly(
        { job_id: 'job-done', reason: :ineligible_state, state: :succeeded },
        { job_id: 'missing', reason: :not_found, state: nil }
      )
      expect(store_state.retry_pending_job_ids).to eq([])
      expect(store_state.queued_job_ids_by_queue.fetch('billing')).to eq(%w[job-failed job-retry])
    end

    it 'reports duplicate requests and uniqueness-conflicted retries as skipped' do
      failed_job = Karya::Job.new(
        id: 'job-failed',
        queue: 'billing',
        handler: 'billing_sync',
        state: :failed,
        created_at:,
        updated_at: created_at + 4,
        failure_classification: :error,
        uniqueness_key: 'account-1',
        uniqueness_scope: :queued
      )
      store.enqueue(
        job: submission_job(id: 'job-blocker', created_at:, uniqueness_key: 'account-1', uniqueness_scope: :queued),
        now: created_at + 5
      )
      store_state.jobs_by_id['job-failed'] = failed_job

      report = store.retry_jobs(job_ids: %w[job-failed job-failed], now: created_at + 10)

      expect(report.changed_jobs).to eq([])
      expect(report.skipped_jobs).to eq(
        [
          { job_id: 'job-failed', reason: :uniqueness_conflict, state: :failed },
          { job_id: 'job-failed', reason: :duplicate_request, state: nil }
        ]
      )
    end

    it 'validates retry job id input' do
      expect { store.retry_jobs(job_ids: 'job-1', now: created_at + 1) }.to raise_error(Karya::InvalidQueueStoreOperationError, /job_ids/)
      expect { store.retry_jobs(job_ids: [nil], now: created_at + 1) }.to raise_error(Karya::InvalidQueueStoreOperationError, /job_id/)
    end
  end

  describe '#cancel_jobs' do
    it 'cancels queued and retry-pending jobs and removes scheduling indexes' do
      store.enqueue(job: submission_job(id: 'job-queued', created_at:), now: created_at + 1)
      retry_job = store.enqueue(job: submission_job(id: 'job-retry', created_at:), now: created_at + 2)
                       .transition_to(:reserved, updated_at: created_at + 3)
                       .transition_to(:running, updated_at: created_at + 4, attempt: 1)
                       .transition_to(:failed, updated_at: created_at + 5, failure_classification: :error)
                       .transition_to(:retry_pending, updated_at: created_at + 6, next_retry_at: created_at + 100)
      store_state.jobs_by_id['job-retry'] = retry_job
      store_state.queued_job_ids_by_queue.fetch('billing').delete('job-retry')
      store_state.register_retry_pending('job-retry')

      report = store.cancel_jobs(job_ids: %w[job-queued job-retry], now: created_at + 10)

      expect(report.changed_jobs.map(&:state)).to eq(%i[cancelled cancelled])
      expect(store_state.queued_job_ids_by_queue).to eq({})
      expect(store_state.retry_pending_job_ids).to eq([])
    end

    it 'tombstones cancelled reservation and execution tokens' do
      store.enqueue(job: submission_job(id: 'job-reserved', created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'job-running', created_at:), now: created_at + 2)
      reserved = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 3)
      running = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 4)
      store.start_execution(reservation_token: running.token, now: created_at + 5)

      report = store.cancel_jobs(job_ids: %w[job-reserved job-running], now: created_at + 6)

      expect(report.changed_jobs.map(&:id)).to eq(%w[job-reserved job-running])
      expect(stored_job('job-reserved').state).to eq(:cancelled)
      expect(stored_job('job-running').state).to eq(:cancelled)
      expect(store_state.reservation_token_for_job('job-reserved')).to be_nil
      expect(store_state.execution_token_for_job('job-running')).to be_nil
      expect do
        store.release(reservation_token: reserved.token, now: created_at + 7)
      end.to raise_error(Karya::ExpiredReservationError)
      expect do
        store.complete_execution(reservation_token: running.token, now: created_at + 8)
      end.to raise_error(Karya::ExpiredReservationError)
    end

    it 'reports duplicate, unknown, and terminal cancellation requests as skipped' do
      store.enqueue(job: submission_job(id: 'job-queued', created_at:), now: created_at + 1)
      succeeded_job = store.enqueue(job: submission_job(id: 'job-done', created_at:), now: created_at + 2)
                           .transition_to(:reserved, updated_at: created_at + 3)
                           .transition_to(:running, updated_at: created_at + 4, attempt: 1)
                           .transition_to(:succeeded, updated_at: created_at + 5)
      store_state.jobs_by_id['job-done'] = succeeded_job
      store_state.queued_job_ids_by_queue.fetch('billing').delete('job-done')

      report = store.cancel_jobs(job_ids: %w[job-queued job-queued missing job-done], now: created_at + 6)

      expect(report.changed_jobs.map(&:id)).to eq(['job-queued'])
      expect(report.skipped_jobs).to eq(
        [
          { job_id: 'job-queued', reason: :duplicate_request, state: nil },
          { job_id: 'missing', reason: :not_found, state: nil },
          { job_id: 'job-done', reason: :ineligible_state, state: :succeeded }
        ]
      )
    end

    it 'handles cancellation when scheduling indexes are already absent or still populated' do
      store.enqueue(job: submission_job(id: 'job-1', created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'job-2', created_at:), now: created_at + 2)
      report = store.cancel_jobs(job_ids: ['job-1'], now: created_at + 3)

      expect(report.changed_jobs.map(&:id)).to eq(['job-1'])
      expect(store_state.queued_job_ids_by_queue.fetch('billing')).to eq(['job-2'])

      orphaned_queued = Karya::Job.new(id: 'orphaned-queued', queue: 'orphaned', handler: 'billing_sync', state: :queued, created_at:)
      orphaned_reserved = Karya::Job.new(id: 'orphaned-reserved', queue: 'billing', handler: 'billing_sync', state: :reserved, created_at:)
      orphaned_running = Karya::Job.new(id: 'orphaned-running', queue: 'billing', handler: 'billing_sync', state: :running, created_at:)
      custom_job = custom_state_job(id: 'custom-job', state: :paused, created_at:)
      store_state.jobs_by_id[orphaned_queued.id] = orphaned_queued
      store_state.jobs_by_id[orphaned_reserved.id] = orphaned_reserved
      store_state.jobs_by_id[orphaned_running.id] = orphaned_running
      store_state.jobs_by_id[custom_job.id] = custom_job

      fallback_report = store.cancel_jobs(
        job_ids: %w[orphaned-queued orphaned-reserved orphaned-running custom-job],
        now: created_at + 4
      )

      expect(fallback_report.changed_jobs.map(&:id)).to eq(%w[orphaned-queued orphaned-reserved orphaned-running custom-job])
      expect(fallback_report.changed_jobs.map(&:state)).to eq(%i[cancelled cancelled cancelled cancelled])
    end

    it 'validates cancel job id input' do
      expect { store.cancel_jobs(job_ids: 'job-1', now: created_at + 1) }.to raise_error(Karya::InvalidQueueStoreOperationError, /job_ids/)
      expect { store.cancel_jobs(job_ids: [nil], now: created_at + 1) }.to raise_error(Karya::InvalidQueueStoreOperationError, /job_id/)
    end
  end

  describe 'queue pause and resume' do
    it 'blocks reservations from a paused queue without mutating queued jobs' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'job-2', queue: 'shipping', created_at:), now: created_at + 2)

      pause_result = store.pause_queue(queue: 'billing', now: created_at + 3)
      reservation = store.reserve(queues: %w[billing shipping], worker_id: 'worker-1', lease_duration: 60, now: created_at + 4)

      expect(pause_result).to have_attributes(action: :pause_queue, queue: 'billing', paused: true, changed: true)
      expect(reservation.job_id).to eq('job-2')
      expect(stored_job('job-1').state).to eq(:queued)
      expect(store_state.queued_job_ids_by_queue.fetch('billing')).to eq(['job-1'])

      resume_result = store.resume_queue(queue: 'billing', now: created_at + 5)
      resumed_reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 6)

      expect(resume_result).to have_attributes(action: :resume_queue, queue: 'billing', paused: false, changed: true)
      expect(resumed_reservation.job_id).to eq('job-1')
    end

    it 'returns unchanged idempotent pause and resume results' do
      first_pause = store.pause_queue(queue: 'billing', now: created_at + 1)
      second_pause = store.pause_queue(queue: 'billing', now: created_at + 2)
      first_resume = store.resume_queue(queue: 'billing', now: created_at + 3)
      second_resume = store.resume_queue(queue: 'billing', now: created_at + 4)

      expect(first_pause.changed).to be(true)
      expect(second_pause.changed).to be(false)
      expect(first_resume.changed).to be(true)
      expect(second_resume.changed).to be(false)
      expect(second_resume).to be_frozen
    end
  end
end
