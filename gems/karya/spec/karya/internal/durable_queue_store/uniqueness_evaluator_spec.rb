# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::UniquenessEvaluator do
  let(:now) { Time.utc(2026, 5, 23, 12, 0, 0) }
  let(:base_job) do
    Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: { 'invoice_id' => 'inv-1' },
      state: :queued,
      created_at: now - 60,
      updated_at: now - 60,
      idempotency_key: 'idem-1',
      uniqueness_key: 'uniq-1',
      uniqueness_scope: :active
    )
  end

  def job_row_for(job)
    Karya::Internal::DurableQueueStore::JobRecord.new(namespace: 'karya', job:).to_h
  end

  def uniqueness_job(id:, state:, uniqueness_key:, uniqueness_scope: :active, **attributes)
    Karya::Job.new(
      id:,
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state:,
      created_at: attributes.fetch(:created_at, now - 60),
      updated_at: attributes.fetch(:updated_at, now - 20),
      uniqueness_key:,
      uniqueness_scope:,
      **attributes.except(:created_at, :updated_at)
    )
  end

  def reservation_row_for(job, token:, phase:, expires_at: now + 30)
    Karya::Internal::DurableQueueStore::ReservationRecord.new(
      namespace: 'karya',
      reservation: Karya::Reservation.new(
        token:,
        job_id: job.id,
        queue: job.queue,
        worker_id: 'worker-1',
        reserved_at: now - 20,
        expires_at:
      ),
      phase:
    ).to_h
  end

  it 'rejects duplicate job ids before evaluating keys' do
    candidate = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :submission,
      created_at: now,
      uniqueness_key: 'uniq-2',
      uniqueness_scope: :active
    )
    evaluator = described_class.new(rows: { jobs: [job_row_for(base_job)] }, now:)

    decision = evaluator.decision_for(job: candidate)

    expect(decision).to include(
      action: :reject,
      result: :duplicate_job_id,
      key_type: :job_id,
      key: 'job-1',
      conflicting_job_id: 'job-1'
    )
  end

  it 'rejects duplicate idempotency keys from durable rows' do
    candidate = Karya::Job.new(
      id: 'job-2',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: { 'invoice_id' => 'inv-2' },
      state: :submission,
      created_at: now,
      idempotency_key: 'idem-1'
    )

    evaluator = described_class.new(rows: { jobs: [job_row_for(base_job)] }, now:)
    decision = evaluator.decision_for(job: candidate)

    expect(decision).to include(
      action: :reject,
      result: :duplicate_idempotency_key,
      conflicting_job_id: 'job-1'
    )
  end

  it 'treats expired running leases as recovered queued blockers for uniqueness' do
    running_job = base_job.transition_to(:reserved, updated_at: now - 30).transition_to(:running, updated_at: now - 20)
    reservation_row = Karya::Internal::DurableQueueStore::ReservationRecord.new(
      namespace: 'karya',
      reservation: Karya::Reservation.new(
        token: 'lease-1',
        job_id: running_job.id,
        queue: running_job.queue,
        worker_id: 'worker-1',
        reserved_at: now - 20,
        expires_at: now - 1
      ),
      phase: :running
    ).to_h

    candidate = Karya::Job.new(
      id: 'job-2',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: { 'invoice_id' => 'inv-2' },
      state: :submission,
      created_at: now,
      uniqueness_key: 'uniq-1',
      uniqueness_scope: :active
    )

    evaluator = described_class.new(rows: { jobs: [job_row_for(running_job)], reservations: [reservation_row] }, now:)
    decision = evaluator.decision_for(job: candidate)

    expect(decision).to include(
      action: :reject,
      result: :duplicate_uniqueness_key,
      conflicting_job_id: 'job-1'
    )
  end

  it 'builds the persisted uniqueness snapshot shape from durable rows' do
    evaluator = described_class.new(rows: { jobs: [job_row_for(base_job)] }, now:)
    snapshot = evaluator.snapshot

    expect(snapshot[:captured_at]).to eq(now)
    expect(snapshot[:idempotency_keys]).to include(
      'idem-1' => include(job_id: 'job-1', state: :queued)
    )
    expect(snapshot[:uniqueness_keys]).to include(
      'uniq-1' => contain_exactly(include(job_id: 'job-1', blocked_incoming_scopes: include(:active)))
    )
  end

  it 'raises the public duplicate enqueue errors from a rejection decision' do
    candidate = Karya::Job.new(
      id: 'job-2',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: { 'invoice_id' => 'inv-2' },
      state: :submission,
      created_at: now,
      uniqueness_key: 'uniq-1',
      uniqueness_scope: :active
    )

    evaluator = described_class.new(rows: { jobs: [job_row_for(base_job)] }, now:)
    decision = evaluator.decision_for(job: candidate)

    expect do
      evaluator.raise_duplicate_enqueue_error(decision)
    end.to raise_error(Karya::DuplicateUniquenessKeyError, /uniq-1/)
  end

  it 'raises the duplicate job error for duplicate job id decisions' do
    evaluator = described_class.new(rows: { jobs: [] }, now:)

    expect do
      evaluator.raise_duplicate_enqueue_error(
        {
          action: :reject,
          result: :duplicate_job_id,
          job_id: 'job-1',
          key: 'job-1'
        }
      )
    end.to raise_error(Karya::DuplicateJobError, /job-1/)
  end

  it 'ignores accepted and unknown rejection decisions when raising duplicate errors' do
    evaluator = described_class.new(rows: { jobs: [] }, now:)

    expect(evaluator.raise_duplicate_enqueue_error(action: :accept)).to be_nil
    expect(evaluator.raise_duplicate_enqueue_error(action: :reject, result: :unknown, job_id: 'job-1', key: 'x')).to be_nil
  end

  it 'does not report blockers for terminal uniqueness scopes or missing uniqueness scope' do
    terminal_job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :succeeded,
      created_at: now - 60,
      updated_at: now - 1,
      uniqueness_key: 'uniq-1',
      uniqueness_scope: :until_terminal
    )
    no_scope_job = Karya::Job.new(
      id: 'job-2',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :queued,
      created_at: now - 30,
      updated_at: now - 30,
      uniqueness_key: 'uniq-2'
    )
    evaluator = described_class.new(
      rows: { jobs: [job_row_for(terminal_job), job_row_for(no_scope_job)] },
      now:
    )

    snapshot = evaluator.snapshot

    expect(snapshot[:uniqueness_keys]).not_to have_key('uniq-1')
    expect(snapshot[:uniqueness_keys]).not_to have_key('uniq-2')
  end

  it 'treats due retry-pending jobs as queued uniqueness blockers' do
    retry_job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :retry_pending,
      created_at: now - 60,
      updated_at: now - 5,
      next_retry_at: now - 1,
      failure_classification: :error,
      uniqueness_key: 'uniq-1',
      uniqueness_scope: :active
    )
    candidate = Karya::Job.new(
      id: 'job-2',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :submission,
      created_at: now,
      uniqueness_key: 'uniq-1',
      uniqueness_scope: :queued
    )
    evaluator = described_class.new(rows: { jobs: [job_row_for(retry_job)] }, now:)

    decision = evaluator.decision_for(job: candidate)

    expect(decision).to include(action: :reject, result: :duplicate_uniqueness_key)
  end

  it 'ignores expired queued jobs and non-expired future retry-pending jobs when evaluating uniqueness' do
    expired_job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :queued,
      created_at: now - 60,
      updated_at: now - 5,
      expires_at: now - 1,
      uniqueness_key: 'uniq-1',
      uniqueness_scope: :active
    )
    future_retry_job = Karya::Job.new(
      id: 'job-2',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :retry_pending,
      created_at: now - 60,
      updated_at: now - 5,
      next_retry_at: now + 60,
      failure_classification: :error,
      uniqueness_key: 'uniq-2',
      uniqueness_scope: :queued
    )
    candidate = Karya::Job.new(
      id: 'job-3',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :submission,
      created_at: now,
      uniqueness_key: 'uniq-3',
      uniqueness_scope: :queued
    )
    evaluator = described_class.new(
      rows: { jobs: [job_row_for(expired_job), job_row_for(future_retry_job)] },
      now:
    )

    decision = evaluator.decision_for(job: candidate)

    expect(decision).to include(action: :accept, result: :accepted)
  end

  it 'treats expired reserved leases as recovered queued uniqueness blockers' do
    reserved_job = base_job.transition_to(:reserved, updated_at: now - 20)
    reservation_row = Karya::Internal::DurableQueueStore::ReservationRecord.new(
      namespace: 'karya',
      reservation: Karya::Reservation.new(
        token: 'lease-1',
        job_id: reserved_job.id,
        queue: reserved_job.queue,
        worker_id: 'worker-1',
        reserved_at: now - 20,
        expires_at: now - 1
      ),
      phase: :reserved
    ).to_h
    candidate = Karya::Job.new(
      id: 'job-2',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :submission,
      created_at: now,
      uniqueness_key: 'uniq-1',
      uniqueness_scope: :active
    )
    evaluator = described_class.new(rows: { jobs: [job_row_for(reserved_job)], reservations: [reservation_row] }, now:)

    decision = evaluator.decision_for(job: candidate)

    expect(decision).to include(action: :reject, result: :duplicate_uniqueness_key)
  end

  it 'skips unsupported reservation phases and falls back to the job queue in reservation rows' do
    reservation_row = {
      reservation_token: 'lease-1',
      job_id: base_job.id,
      worker_id: 'worker-1',
      reserved_at: now - 5,
      lease_expires_at: now + 5,
      phase: :unknown
    }
    evaluator = described_class.new(rows: { jobs: [job_row_for(base_job)], reservations: [reservation_row] }, now:)

    reservations_by_phase = evaluator.send(:reservations_by_phase)

    expect(reservations_by_phase).to eq(reserved: [], running: [])
  end

  it 'returns false for unknown uniqueness scopes' do
    evaluator = described_class.new(rows: { jobs: [] }, now:)

    expect(evaluator.send(:uniqueness_scope_blocks_state?, :custom, :queued)).to be(false)
  end

  it 'covers duplicate-idempotency and retry/expiry uniqueness branches' do
    duplicate_id_job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :submission,
      created_at: now,
      idempotency_key: 'idem-1',
      uniqueness_key: 'uniq-1',
      uniqueness_scope: :active
    )
    expired_retry = uniqueness_job(id: 'job-3', state: :retry_pending, uniqueness_key: 'uniq-3', expires_at: now - 1, next_retry_at: now - 5)
    future_retry = uniqueness_job(id: 'job-4', state: :retry_pending, uniqueness_key: 'uniq-4', next_retry_at: now + 30)
    evaluator = described_class.new(rows: { jobs: [job_row_for(base_job), job_row_for(expired_retry), job_row_for(future_retry)] }, now:)

    expect(evaluator.send(:duplicate_idempotency_job, duplicate_id_job)).to be_nil
    expect(evaluator.send(:duplicate_uniqueness_job, duplicate_id_job)).to be_nil
    expired_queued = uniqueness_job(id: 'job-expired', state: :queued, uniqueness_key: 'uniq-expired', expires_at: now - 1)
    expect(evaluator.send(:effective_uniqueness_job, expired_queued)).to be_nil
    expect(evaluator.send(:effective_uniqueness_job, expired_retry)).to be_nil
    expect(evaluator.send(:effective_uniqueness_job, future_retry)).to eq(future_retry)
  end

  it 'covers reserved and running uniqueness lease branches' do
    reserved_job = uniqueness_job(id: 'job-5', state: :reserved, uniqueness_key: 'uniq-5')
    running_job = uniqueness_job(id: 'job-6', state: :running, uniqueness_key: 'uniq-6')
    evaluator = described_class.new(
      rows: {
        jobs: [job_row_for(reserved_job), job_row_for(running_job)],
        reservations: [
          reservation_row_for(reserved_job, token: 'lease-5', phase: :reserved),
          reservation_row_for(running_job, token: 'lease-6', phase: :running)
        ]
      },
      now:
    )

    expect(evaluator.send(:effective_uniqueness_job, reserved_job)).to eq(reserved_job)
    expect(evaluator.send(:effective_uniqueness_job, running_job)).to eq(running_job)
  end

  it 'covers non-conflicting and expired reserved uniqueness branches' do
    no_scope_existing = uniqueness_job(id: 'job-2', state: :succeeded, uniqueness_key: 'uniq-1', uniqueness_scope: nil)
    no_conflict_evaluator = described_class.new(rows: { jobs: [job_row_for(no_scope_existing)] }, now:)
    expect(
      no_conflict_evaluator.send(
        :duplicate_uniqueness_job,
        Karya::Job.new(
          id: 'job-incoming',
          queue: 'billing',
          handler: 'ProcessInvoice',
          arguments: {},
          state: :submission,
          created_at: now,
          uniqueness_key: 'uniq-1',
          uniqueness_scope: :queued
        )
      )
    ).to be_nil

    expired_reserved = uniqueness_job(id: 'job-7', state: :reserved, uniqueness_key: 'uniq-7', expires_at: now - 1)
    evaluator = described_class.new(rows: { jobs: [job_row_for(expired_reserved)] }, now:)
    expect(evaluator.send(:effective_uniqueness_job, expired_reserved)).to be_nil
  end

  it 'omits expired retry blockers from the uniqueness snapshot' do
    expired_retry = uniqueness_job(id: 'job-3', state: :retry_pending, uniqueness_key: 'uniq-3', expires_at: now - 1, next_retry_at: now - 5)
    evaluator = described_class.new(rows: { jobs: [job_row_for(expired_retry)] }, now:)
    snapshot = evaluator.snapshot
    expect(snapshot[:uniqueness_keys]).not_to have_key('uniq-3')
  end

  it 'skips uniqueness snapshot entries without keys and without effective blockers' do
    no_key_job = Karya::Job.new(
      id: 'job-8',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :queued,
      created_at: now - 10,
      updated_at: now - 10
    )
    expired_unique_job = Karya::Job.new(
      id: 'job-9',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :queued,
      created_at: now - 60,
      updated_at: now - 60,
      expires_at: now - 1,
      uniqueness_key: 'uniq-9',
      uniqueness_scope: :active
    )
    evaluator = described_class.new(rows: { jobs: [job_row_for(no_key_job), job_row_for(expired_unique_job)] }, now:)

    expect(evaluator.snapshot[:uniqueness_keys]).to eq({})
  end

  it 'covers duplicate_uniqueness_job nil branches for expired and non-conflicting scoped jobs' do
    expired_existing = Karya::Job.new(
      id: 'job-expired-existing',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :queued,
      created_at: now - 60,
      updated_at: now - 60,
      expires_at: now - 1,
      uniqueness_key: 'uniq-expired-existing',
      uniqueness_scope: :active
    )
    non_conflicting_existing = Karya::Job.new(
      id: 'job-non-conflicting',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :succeeded,
      created_at: now - 60,
      updated_at: now - 10,
      uniqueness_key: 'uniq-non-conflicting',
      uniqueness_scope: :active
    )

    expired_evaluator = described_class.new(rows: { jobs: [job_row_for(expired_existing)] }, now:)
    conflict_evaluator = described_class.new(rows: { jobs: [job_row_for(non_conflicting_existing)] }, now:)

    expect(
      expired_evaluator.send(
        :duplicate_uniqueness_job,
        Karya::Job.new(
          id: 'incoming-expired',
          queue: 'billing',
          handler: 'ProcessInvoice',
          arguments: {},
          state: :submission,
          created_at: now,
          uniqueness_key: 'uniq-expired-existing',
          uniqueness_scope: :active
        )
      )
    ).to be_nil
    expect(
      conflict_evaluator.send(
        :duplicate_uniqueness_job,
        Karya::Job.new(
          id: 'incoming-non-conflicting',
          queue: 'billing',
          handler: 'ProcessInvoice',
          arguments: {},
          state: :submission,
          created_at: now,
          uniqueness_key: 'uniq-non-conflicting',
          uniqueness_scope: :queued
        )
      )
    ).to be_nil
  end

  it 'covers the secondary uniqueness conflict branch for active existing jobs' do
    evaluator = described_class.new(rows: { jobs: [] }, now:)
    existing_job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :queued,
      created_at: now - 60,
      uniqueness_key: 'uniq-1',
      uniqueness_scope: :active
    )
    incoming_job = Karya::Job.new(
      id: 'job-2',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :submission,
      created_at: now,
      uniqueness_key: 'uniq-1',
      uniqueness_scope: :queued
    )

    expect(evaluator.send(:uniqueness_conflict_between?, existing_job, incoming_job)).to be(true)
  end
end
