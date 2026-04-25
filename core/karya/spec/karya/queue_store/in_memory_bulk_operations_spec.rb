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
      expect(store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2).job_id).to eq('job-1')
      expect(store.reserve(queue: 'shipping', worker_id: 'worker-2', lease_duration: 30, now: created_at + 3).job_id).to eq('job-2')
    end

    it 'atomically creates an immutable workflow batch when batch_id is provided' do
      report = store.enqueue_many(
        jobs: [
          submission_job(id: 'job-1', created_at:),
          submission_job(id: 'job-2', created_at:)
        ],
        now: created_at + 1,
        batch_id: :invoice_closeout
      )
      snapshot = store.batch_snapshot(batch_id: ' invoice_closeout ', now: created_at + 2)

      expect(report.changed_jobs.map(&:id)).to eq(%w[job-1 job-2])
      expect(snapshot).to have_attributes(
        batch_id: 'invoice_closeout',
        job_ids: %w[job-1 job-2],
        total_count: 2,
        completed_count: 0,
        failed_count: 0,
        aggregate_state: :running
      )
      expect(snapshot.state_counts).to eq(queued: 2)
    end

    it 'rejects duplicate batch ids without partial writes' do
      store.enqueue_many(jobs: [submission_job(id: 'job-1', created_at:)], now: created_at + 1, batch_id: 'batch_1')

      expect do
        store.enqueue_many(jobs: [submission_job(id: 'job-2', created_at:)], now: created_at + 2, batch_id: ' batch_1 ')
      end.to raise_error(Karya::Workflow::DuplicateBatchError, 'batch "batch_1" already exists')

      expect(store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3).job_id).to eq('job-1')
      expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4)).to be_nil
    end

    it 'rejects oversize workflow batches without partial writes' do
      limited_store = described_class.new(max_batch_size: 1)

      expect do
        limited_store.enqueue_many(
          jobs: [
            submission_job(id: 'job-1', created_at:),
            submission_job(id: 'job-2', created_at:)
          ],
          now: created_at + 1,
          batch_id: 'batch_1'
        )
      end.to raise_error(Karya::Workflow::InvalidBatchError, 'batch size must be at most 1 job')

      expect(limited_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)).to be_nil
    end

    it 'rejects invalid batch ids without partial writes' do
      expect do
        store.enqueue_many(
          jobs: [submission_job(id: 'job-1', created_at:)],
          now: created_at + 1,
          batch_id: '   '
        )
      end.to raise_error(Karya::Workflow::InvalidBatchError, 'batch_id must be present')

      expect(store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)).to be_nil
    end

    it 'prunes old terminal batches after the completed batch retention limit' do
      tokens = %w[lease-1 lease-2].each
      limited_store = described_class.new(completed_batch_retention_limit: 1, token_generator: -> { tokens.next })
      limited_store.enqueue_many(
        jobs: [submission_job(id: 'job-1', created_at:)],
        now: created_at + 1,
        batch_id: 'batch_1'
      )
      first = limited_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      limited_store.start_execution(reservation_token: first.token, now: created_at + 3)
      limited_store.complete_execution(reservation_token: first.token, now: created_at + 4)

      limited_store.enqueue_many(
        jobs: [submission_job(id: 'job-2', created_at:)],
        now: created_at + 5,
        batch_id: 'batch_2'
      )
      second = limited_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 6)
      limited_store.start_execution(reservation_token: second.token, now: created_at + 7)
      limited_store.complete_execution(reservation_token: second.token, now: created_at + 8)

      expect do
        limited_store.batch_snapshot(batch_id: 'batch_1', now: created_at + 9)
      end.to raise_error(Karya::Workflow::UnknownBatchError, 'batch "batch_1" is not registered')
      expect(limited_store.batch_snapshot(batch_id: 'batch_2', now: created_at + 9).job_ids).to eq(['job-2'])
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

      expect(store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)).to be_nil
    end

    it 'rejects in-batch duplicate job ids before other conflicts' do
      jobs = [
        submission_job(id: 'job-1', created_at:, idempotency_key: 'same-key'),
        submission_job(id: 'job-1', created_at:, idempotency_key: 'same-key')
      ]

      expect do
        store.enqueue_many(jobs:, now: created_at + 1)
      end.to raise_error(Karya::DuplicateJobError, /job-1/)

      expect(store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)).to be_nil
    end

    it 'rejects in-batch duplicate uniqueness keys without partial writes' do
      jobs = [
        submission_job(id: 'job-1', created_at:, uniqueness_key: 'account-1', uniqueness_scope: :queued),
        submission_job(id: 'job-2', created_at:, uniqueness_key: 'account-1', uniqueness_scope: :queued)
      ]

      expect do
        store.enqueue_many(jobs:, now: created_at + 1)
      end.to raise_error(Karya::DuplicateUniquenessKeyError, /account-1/)

      expect(store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)).to be_nil
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

      expect(store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3).job_id).to eq('job-1')
      expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4)).to be_nil
    end

    it 'validates batch inputs before writing' do
      queued_job = submission_job(id: 'job-1', created_at:).transition_to(:queued, updated_at: created_at + 1)

      expect { store.enqueue_many(jobs: 'job-1', now: created_at + 2) }.to raise_error(Karya::InvalidEnqueueError, /jobs/)
      expect { store.enqueue_many(jobs: ['job-1'], now: created_at + 2) }.to raise_error(Karya::InvalidEnqueueError, /Karya::Job/)
      expect { store.enqueue_many(jobs: [queued_job], now: created_at + 2) }.to raise_error(Karya::InvalidEnqueueError, /submission/)
      expect(store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)).to be_nil
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

    it 'does not create a batch when enqueue validation fails' do
      jobs = [
        submission_job(id: 'job-1', created_at:, idempotency_key: 'same-key'),
        submission_job(id: 'job-2', created_at:, idempotency_key: 'same-key')
      ]

      expect do
        store.enqueue_many(jobs:, now: created_at + 1, batch_id: 'batch_1')
      end.to raise_error(Karya::DuplicateIdempotencyKeyError, /same-key/)

      expect do
        store.batch_snapshot(batch_id: 'batch_1', now: created_at + 2)
      end.to raise_error(Karya::Workflow::UnknownBatchError, 'batch "batch_1" is not registered')
      expect(store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)).to be_nil
    end

    it 'reflects current member job states in batch snapshots' do
      retry_policy = Karya::RetryPolicy.new(max_attempts: 3, base_delay: 60, multiplier: 1)
      store.enqueue_many(
        jobs: %w[job-reserved job-running job-retry job-failed job-dead job-cancelled job-queued].map do |job_id|
          submission_job(id: job_id, created_at:)
        end,
        now: created_at + 1,
        batch_id: 'batch_1'
      )
      reserved = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 2)
      running = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 3)
      retry_pending = store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 60, now: created_at + 4)
      failed = store.reserve(queue: 'billing', worker_id: 'worker-4', lease_duration: 60, now: created_at + 5)
      store.start_execution(reservation_token: running.token, now: created_at + 6)
      store.start_execution(reservation_token: retry_pending.token, now: created_at + 7)
      store.fail_execution(reservation_token: retry_pending.token, now: created_at + 8, retry_policy:, failure_classification: :error)
      store.start_execution(reservation_token: failed.token, now: created_at + 9)
      store.fail_execution(reservation_token: failed.token, now: created_at + 10, failure_classification: :error)
      store.dead_letter_jobs(job_ids: ['job-dead'], now: created_at + 11, reason: 'operator isolated')
      store.cancel_jobs(job_ids: ['job-cancelled'], now: created_at + 12)

      snapshot = store.batch_snapshot(batch_id: 'batch_1', now: created_at + 13)

      expect(snapshot.jobs.map(&:id)).to eq(%w[job-reserved job-running job-retry job-failed job-dead job-cancelled job-queued])
      expect(snapshot.state_counts).to eq(
        reserved: 1,
        running: 1,
        retry_pending: 1,
        failed: 1,
        dead_letter: 1,
        cancelled: 1,
        queued: 1
      )
      expect(snapshot.failed_count).to eq(2)
      expect(snapshot.completed_count).to eq(1)
      expect(snapshot.aggregate_state).to eq(:failed)
      expect(reserved.job_id).to eq('job-reserved')
    end

    it 'derives terminal aggregate states from snapshots' do
      store.enqueue_many(
        jobs: [submission_job(id: 'job-1', created_at:), submission_job(id: 'job-2', created_at:)],
        now: created_at + 1,
        batch_id: :successful_batch
      )
      first = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 2)
      second = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 3)
      store.start_execution(reservation_token: first.token, now: created_at + 4)
      store.complete_execution(reservation_token: first.token, now: created_at + 5)
      store.start_execution(reservation_token: second.token, now: created_at + 6)
      store.complete_execution(reservation_token: second.token, now: created_at + 7)

      expect(store.batch_snapshot(batch_id: :successful_batch, now: created_at + 8).aggregate_state).to eq(:succeeded)

      store.enqueue_many(
        jobs: [submission_job(id: 'job-3', created_at:), submission_job(id: 'job-4', created_at:)],
        now: created_at + 9,
        batch_id: :mixed_terminal_batch
      )
      third = store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 60, now: created_at + 10)
      store.start_execution(reservation_token: third.token, now: created_at + 11)
      store.complete_execution(reservation_token: third.token, now: created_at + 12)
      store.cancel_jobs(job_ids: ['job-4'], now: created_at + 13)

      expect(store.batch_snapshot(batch_id: :mixed_terminal_batch, now: created_at + 14).aggregate_state).to eq(:completed)
    end

    it 'raises a workflow-domain error for unknown batch snapshots' do
      expect do
        store.batch_snapshot(batch_id: :missing, now: created_at + 1)
      end.to raise_error(Karya::Workflow::UnknownBatchError, 'batch "missing" is not registered')
    end
  end

  describe '#retry_jobs' do
    it 'requeues failed and retry-pending jobs and reports ineligible jobs' do
      retry_policy = Karya::RetryPolicy.new(max_attempts: 3, base_delay: 60, multiplier: 1)
      store.enqueue(job: submission_job(id: 'job-failed', created_at:), now: created_at + 1)
      failed_reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 2)
      store.start_execution(reservation_token: failed_reservation.token, now: created_at + 3)
      store.fail_execution(reservation_token: failed_reservation.token, now: created_at + 4, failure_classification: :error)

      store.enqueue(job: submission_job(id: 'job-retry', created_at:), now: created_at + 5)
      retry_reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 6)
      store.start_execution(reservation_token: retry_reservation.token, now: created_at + 7)
      store.fail_execution(
        reservation_token: retry_reservation.token,
        now: created_at + 8,
        retry_policy:,
        failure_classification: :error
      )

      store.enqueue(job: submission_job(id: 'job-done', created_at:), now: created_at + 9)
      done_reservation = store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 60, now: created_at + 10)
      store.start_execution(reservation_token: done_reservation.token, now: created_at + 11)
      store.complete_execution(reservation_token: done_reservation.token, now: created_at + 12)

      report = store.retry_jobs(job_ids: %w[job-failed job-retry job-done missing], now: created_at + 20)

      expect(report.changed_jobs.map(&:id)).to eq(%w[job-failed job-retry])
      expect(report.changed_jobs.map(&:state)).to eq(%i[queued queued])
      expect(report.skipped_jobs).to contain_exactly(
        { job_id: 'job-done', reason: :ineligible_state, state: :succeeded },
        { job_id: 'missing', reason: :not_found, state: nil }
      )
      expect(store.reserve(queue: 'billing', worker_id: 'worker-4', lease_duration: 60, now: created_at + 21).job_id).to eq('job-failed')
      expect(store.reserve(queue: 'billing', worker_id: 'worker-5', lease_duration: 60, now: created_at + 22).job_id).to eq('job-retry')
    end

    it 'reports duplicate requests and uniqueness-conflicted retries as skipped' do
      store.enqueue(
        job: submission_job(
          id: 'job-failed',
          created_at:,
          uniqueness_key: 'account-1',
          uniqueness_scope: :queued
        ),
        now: created_at + 1
      )
      failed_reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 2)
      store.start_execution(reservation_token: failed_reservation.token, now: created_at + 3)
      store.fail_execution(reservation_token: failed_reservation.token, now: created_at + 4, failure_classification: :error)
      store.enqueue(
        job: submission_job(id: 'job-blocker', created_at:, uniqueness_key: 'account-1', uniqueness_scope: :queued),
        now: created_at + 5
      )

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
      retry_policy = Karya::RetryPolicy.new(max_attempts: 3, base_delay: 60, multiplier: 1)
      store.enqueue(job: submission_job(id: 'job-retry', created_at:), now: created_at + 2)
      retry_reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 3)
      store.start_execution(reservation_token: retry_reservation.token, now: created_at + 4)
      store.fail_execution(
        reservation_token: retry_reservation.token,
        now: created_at + 5,
        retry_policy:,
        failure_classification: :error
      )

      report = store.cancel_jobs(job_ids: %w[job-queued job-retry], now: created_at + 10)

      expect(report.changed_jobs.map(&:state)).to eq(%i[cancelled cancelled])
      expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 11)).to be_nil
    end

    it 'tombstones cancelled reservation and execution tokens' do
      store.enqueue(job: submission_job(id: 'job-reserved', created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'job-running', created_at:), now: created_at + 2)
      reserved = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 3)
      running = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 4)
      store.start_execution(reservation_token: running.token, now: created_at + 5)

      report = store.cancel_jobs(job_ids: %w[job-reserved job-running], now: created_at + 6)

      expect(report.changed_jobs.map(&:id)).to eq(%w[job-reserved job-running])
      expect do
        store.release(reservation_token: reserved.token, now: created_at + 7)
      end.to raise_error(Karya::ExpiredReservationError)
      expect do
        store.complete_execution(reservation_token: running.token, now: created_at + 8)
      end.to raise_error(Karya::ExpiredReservationError)
    end

    it 'reports duplicate, unknown, and terminal cancellation requests as skipped' do
      store.enqueue(job: submission_job(id: 'job-queued', created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'job-done', created_at:, queue: 'shipping'), now: created_at + 2)
      done_reservation = store.reserve(queue: 'shipping', worker_id: 'worker-1', lease_duration: 60, now: created_at + 3)
      store.start_execution(reservation_token: done_reservation.token, now: created_at + 4)
      store.complete_execution(reservation_token: done_reservation.token, now: created_at + 5)

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
