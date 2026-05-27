# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::Operations do
  include_context 'with durable queue-store operations spec support'

  it 'maps reservation tokens back to jobs and records not-found bulk skips' do
    queued_job = job(id: 'job-1', state: :queued)
    rows = {
      jobs: [job_row(queued_job), job_row(job(id: 'job-2', state: :queued))],
      reservations: [reservation_row(job: queued_job, token: 'token-1', phase: :reserved)],
      queue_entries: []
    }
    helper = helper_class.new(store:, request: {})

    expect(Karya::Internal::DurableQueueStore::Operations::RowIndex.new(rows:).reservation_to_job_map.fetch('token-1')).to have_attributes(id: 'job-1')
    replaced_rows = helper.send(:update_rows_with_job, rows.merge(namespace:), 'job-1', job(id: 'job-1', state: :failed))
    expect(Karya::Internal::DurableQueueStore::Operations::JobRow.new(row: replaced_rows.fetch(:jobs).last).to_job.state).to eq(:queued)

    skipped_jobs = []
    expect(
      Karya::Internal::DurableQueueStore::Operations::BulkJobLookup.new(
        namespace:,
        rows: rows.merge(namespace:),
        job_id: 'missing',
        skipped_jobs:
      ).load
    ).to be_nil
    expect(skipped_jobs).to eq([{ job_id: 'missing', reason: :not_found, state: nil }])
  end

  it 'updates stored job rows and groups policy rows by kind' do
    queued_job = job(id: 'job-1', state: :queued)
    failed_job = job(id: 'job-1', state: :failed)
    rows = {
      namespace:,
      jobs: [job_row(queued_job)],
      policy_state: [
        policy_row(policy_kind: 'breaker_state', scope_kind: 'queue', scope_value: 'billing', state_payload: { state: :open }),
        policy_row(policy_kind: 'breaker_failures', scope_kind: 'queue', scope_value: 'billing', state_payload: { failures: [now] })
      ]
    }
    helper = helper_class.new(store:, request: {})

    updated_rows = helper.send(:update_rows_with_job, rows, 'job-1', failed_job)

    expect(Karya::Internal::DurableQueueStore::Operations::JobRow.new(row: updated_rows.fetch(:jobs).first).to_job.state).to eq(:failed)
    expect(helper.send(:policy_rows_by_kind, rows).keys).to contain_exactly('breaker_state', 'breaker_failures')
    expect(helper.send(:policy_scope_key, scope_kind: 'queue', scope_value: '')).to eq('')
  end

  it 'raises expired reservation errors' do
    helper = helper_class.new(store:, request: {})

    expect do
      helper.send(
        :raise_expired_reservation_error!,
        'token-1',
        { lease_expires_at: now - 1 },
        now
      )
    end.to raise_error(Karya::ExpiredReservationError, /token-1/)
  end

  it 'skips ineligible and uniqueness-conflicting dead-letter recoveries' do
    blocker = job(id: 'job-1', state: :queued, uniqueness_key: 'uniq-1', uniqueness_scope: :active)
    dead_job = job(id: 'job-2', state: :dead_letter, uniqueness_key: 'uniq-1', uniqueness_scope: :active)
    queued_job = job(id: 'job-3', state: :queued)
    rows = {
      jobs: [job_row(blocker), job_row(dead_job), job_row(queued_job)],
      queue_entries: [queue_entry_row(blocker), queue_entry_row(queued_job, insertion_sequence: 2)],
      reservations: []
    }

    replay = described_class::ReplayDeadLetterJobs.new(
      store:,
      request: { job_ids: %w[job-2 job-3], now: },
      operation_name: :replay_dead_letter_jobs
    ).call(context: context(rows:))

    expect(replay.value.skipped_jobs).to contain_exactly(
      { job_id: 'job-2', reason: :uniqueness_conflict, state: :dead_letter },
      { job_id: 'job-3', reason: :ineligible_state, state: :queued }
    )
  end

  it 'skips ineligible retry, cancel, and dead-letter requests' do
    queued_job = job(id: 'job-1', state: :queued)
    succeeded_job = job(id: 'job-2', state: :succeeded)
    cancelled_job = job(id: 'job-3', state: :cancelled)
    rows = { jobs: [job_row(queued_job), job_row(succeeded_job), job_row(cancelled_job)], queue_entries: [], reservations: [] }

    retry_report = described_class::RetryJobs.new(
      store:,
      request: { job_ids: ['job-1'], now: },
      operation_name: :retry_jobs
    ).call(context: context(rows:))
    cancel_report = described_class::CancelJobs.new(
      store:,
      request: { job_ids: ['job-2'], now: },
      operation_name: :cancel_jobs
    ).call(context: context(rows:))
    dead_letter_report = described_class::DeadLetterJobs.new(
      store:,
      request: { job_ids: ['job-3'], now:, reason: 'manual' },
      operation_name: :dead_letter_jobs
    ).call(context: context(rows:))

    expect(retry_report.value.skipped_jobs).to eq([{ job_id: 'job-1', reason: :ineligible_state, state: :queued }])
    expect(cancel_report.value.skipped_jobs).to eq([{ job_id: 'job-2', reason: :ineligible_state, state: :succeeded }])
    expect(dead_letter_report.value.skipped_jobs).to eq([{ job_id: 'job-3', reason: :ineligible_state, state: :cancelled }])
  end

  it 'skips retry conflicts and supports retry-pending immediate retries' do
    blocker = job(id: 'job-1', state: :queued, uniqueness_key: 'uniq-1', uniqueness_scope: :active)
    failed_job = job(id: 'job-2', state: :failed, uniqueness_key: 'uniq-1', uniqueness_scope: :active)
    retry_pending_job = job(id: 'job-3', state: :retry_pending, next_retry_at: now + 30)
    rows = {
      jobs: [job_row(blocker), job_row(failed_job), job_row(retry_pending_job)],
      queue_entries: [queue_entry_row(blocker)],
      reservations: []
    }

    conflict_report = described_class::RetryJobs.new(
      store:,
      request: { job_ids: ['job-2'], now: },
      operation_name: :retry_jobs
    ).call(context: context(rows:))
    success_report = described_class::RetryJobs.new(
      store:,
      request: { job_ids: ['job-3'], now: },
      operation_name: :retry_jobs
    ).call(context: context(rows:))

    expect(conflict_report.value.skipped_jobs).to eq([{ job_id: 'job-2', reason: :uniqueness_conflict, state: :failed }])
    expect(success_report.value.changed_jobs.map(&:state)).to eq([:queued])
  end

  it 'builds failed execution outcomes for escalate and fail decisions' do
    operation = described_class::FailExecution.new(store:, request: {}, operation_name: :fail_execution)
    running_job = job(id: 'job-1', state: :running, attempt: 1)
    retry_policy_class = Class.new(Karya::RetryPolicy) do
      def initialize(decisions, **attributes)
        @decisions = decisions
        super(**attributes)
      end

      def decision_for(**)
        @decisions.shift
      end
    end
    decision_class = Struct.new(:action, :delay, :reason)
    retry_policy = retry_policy_class.new(
      [
        decision_class.new(:escalate, nil, :retry_exhausted),
        decision_class.new(:discard, nil, nil)
      ],
      max_attempts: 3,
      base_delay: 1,
      multiplier: 1
    )

    escalated = operation.send(:finalize_failed_job, running_job, now, retry_policy, :error)
    failed = operation.send(:finalize_failed_job, running_job, now, retry_policy, :timeout)

    expect(escalated.state).to eq(:dead_letter)
    expect(escalated.dead_letter_reason).to eq('retry-policy-exhausted')
    expect(failed.state).to eq(:failed)
  end

  it 'rejects invalid uniqueness decision requests' do
    rows = { jobs: [], queue_entries: [], reservations: [] }
    operation = described_class::UniquenessDecision.new(
      store:,
      request: { job: Object.new, now: now },
      operation_name: :uniqueness_decision
    )

    expect do
      operation.call(context: context(rows:))
    end.to raise_error(Karya::InvalidEnqueueError, /Karya::Job/)

    queued_job = job(id: 'job-1', state: :queued)
    expect do
      described_class::UniquenessDecision.new(
        store:,
        request: { job: queued_job, now: now },
        operation_name: :uniqueness_decision
      ).call(context: context(rows:))
    end.to raise_error(Karya::InvalidEnqueueError, /:submission/)

    submission_job = job(id: 'job-2', state: :submission)
    expect do
      described_class::UniquenessDecision.new(
        store:,
        request: { job: submission_job, now: 'now' },
        operation_name: :uniqueness_decision
      ).call(context: context(rows:))
    end.to raise_error(Karya::InvalidEnqueueError, /now must be a Time/)

    valid_result = described_class::UniquenessDecision.new(
      store:,
      request: { job: submission_job, now: now },
      operation_name: :uniqueness_decision
    ).call(context: context(rows:))
    expect(valid_result.value).to include(action: :accept, result: :accepted)
  end

  it 'rejects duplicate batch conflicts before enqueue_many persists rows' do
    accepted_job = job(id: 'job-1', state: :queued, idempotency_key: 'idem-1', uniqueness_key: 'uniq-1', uniqueness_scope: :active)

    expect do
      described_class::EnqueueMany::DuplicateBatchGuard.new(job: accepted_job, accepted_jobs: [accepted_job], now:).validate
    end.to raise_error(Karya::DuplicateJobError, /job-1/)

    expect do
      described_class::EnqueueMany::DuplicateBatchGuard.new(
        job: job(id: 'job-2', state: :submission, idempotency_key: 'idem-1'),
        accepted_jobs: [accepted_job],
        now:
      ).validate
    end.to raise_error(Karya::DuplicateIdempotencyKeyError, /idem-1/)

    expect do
      described_class::EnqueueMany::DuplicateBatchGuard.new(
        job: job(id: 'job-3', state: :submission, uniqueness_key: 'uniq-1', uniqueness_scope: :active),
        accepted_jobs: [accepted_job],
        now:
      ).validate
    end.to raise_error(Karya::DuplicateUniquenessKeyError, /uniq-1/)
  end

  it 'rejects duplicate batches and malformed batch membership' do
    existing_batches = [workflow_batch_row(batch_id: 'batch-1')]

    expect do
      described_class::EnqueueMany::OptionalBatchBuilder.new(
        request: { batch_id: 'batch-1' },
        jobs: [job(id: 'job-1', state: :submission)],
        now:,
        max_batch_size: store.send(:max_batch_size),
        existing_batches:
      ).build
    end.to raise_error(Karya::Workflow::DuplicateBatchError, /batch-1/)

    batch_snapshot = described_class::BatchSnapshot.new(
      store:,
      request: { batch_id: 'batch-1', now: },
      operation_name: :batch_snapshot
    )
    rows = {
      jobs: [],
      queue_entries: [],
      reservations: [],
      workflow_batches: [workflow_batch_row(batch_id: 'batch-1')],
      workflow_steps: [workflow_step_row(batch_id: 'batch-1', step_id: 'step-1', job_id: 'missing')]
    }

    expect do
      batch_snapshot.call(context: context(rows:))
    end.to raise_error(Karya::Workflow::InvalidBatchError, /member job "missing" is not registered/)
  end

  it 'covers alternate batch, bulk-mutation, and lease helper branches' do
    helper = helper_class.new(store:, request: {})
    unknown_batch_rows = { workflow_batches: [], workflow_steps: [] }

    expect do
      Karya::Internal::DurableQueueStore::Operations::WorkflowBatchBuilder.new(rows: unknown_batch_rows, batch_id: 'missing-batch').build
    end.to raise_error(Karya::Workflow::UnknownBatchError, /missing-batch/)

    expect do
      helper.send(:normalize_job_ids, 'job-1')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /job_ids must be an Array/)

    missing_report = helper.send(
      :bulk_mutation_result,
      context(rows: { jobs: [], queue_entries: [], reservations: [] }),
      action: :retry_jobs,
      job_ids: ['missing'],
      now:
    ) do |_job, _rows, _skipped_jobs, _job_id|
      raise 'should not run'
    end
    expect(missing_report.value.skipped_jobs).to eq([{ job_id: 'missing', reason: :not_found, state: nil }])

    lease_helper = described_class::Release.new(
      store:,
      request: { reservation_token: 'missing', now: },
      operation_name: :release
    )
    expect do
      lease_helper.send(:lease_context, context(rows: { jobs: [], reservations: [], queue_entries: [] }))
    end.to raise_error(Karya::UnknownReservationError, /missing/)
  end

  it 'rejects invalid enqueue and enqueue_many requests' do
    enqueue = described_class::Enqueue.new(store:, request: { job: Object.new, now: }, operation_name: :enqueue)
    expect do
      enqueue.call(context: context(rows: { jobs: [], queue_entries: [], reservations: [] }))
    end.to raise_error(Karya::InvalidEnqueueError, /Karya::Job/)

    submission_job = job(id: 'job-submission', state: :submission)
    expect do
      described_class::Enqueue.new(
        store:,
        request: { job: submission_job.transition_to(:queued, updated_at: now), now: },
        operation_name: :enqueue
      ).call(context: context(rows: { jobs: [], queue_entries: [], reservations: [] }))
    end.to raise_error(Karya::InvalidEnqueueError, /:submission/)

    expect do
      described_class::Enqueue.new(
        store:,
        request: { job: submission_job, now: 'now' },
        operation_name: :enqueue
      ).call(context: context(rows: { jobs: [], queue_entries: [], reservations: [] }))
    end.to raise_error(Karya::InvalidEnqueueError, /now must be a Time/)

    expect do
      described_class::EnqueueMany.new(store:, request: { now: 'now', jobs: [] }, operation_name: :enqueue_many).call(context: empty_context)
    end.to raise_error(Karya::InvalidEnqueueError, /now must be a Time/)

    expect do
      described_class::EnqueueMany.new(store:, request: { now:, jobs: 'jobs' }, operation_name: :enqueue_many).call(context: empty_context)
    end.to raise_error(Karya::InvalidEnqueueError, /jobs must be an Array/)

    expect do
      described_class::EnqueueMany.new(store:, request: { now:, jobs: [Object.new] }, operation_name: :enqueue_many).call(context: empty_context)
    end.to raise_error(Karya::InvalidEnqueueError, /jobs entries must be Karya::Job/)

    expect do
      described_class::EnqueueMany.new(store:, request: { now:, jobs: [job(id: 'queued', state: :queued)] },
                                       operation_name: :enqueue_many).call(context: empty_context)
    end.to raise_error(Karya::InvalidEnqueueError, /:submission/)
  end

  it 'rejects invalid uniqueness snapshot requests' do
    expect do
      described_class::UniquenessSnapshot.new(
        store:,
        request: { now: 'now' },
        operation_name: :uniqueness_snapshot
      ).call(context: context(rows: { jobs: [], queue_entries: [], reservations: [] }))
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /now must be a Time/)
  end

  it 'covers failed-execution alternate dead-letter reasons' do
    operation = described_class::FailExecution.new(store:, request: {}, operation_name: :fail_execution)
    running_job = job(id: 'job-1', state: :running, attempt: 1)
    retry_policy_class = Class.new(Karya::RetryPolicy) do
      def decision_for(**)
        Struct.new(:action, :delay, :reason).new(:escalate, nil, :manual)
      end
    end
    retry_policy = retry_policy_class.new(max_attempts: 3, base_delay: 1, multiplier: 1)

    escalated = operation.send(:finalize_failed_job, running_job, now, retry_policy, :error)
    expect(escalated.dead_letter_reason).to eq('retry-policy-escalated')
  end

  it 'covers bulk enqueue insert branches and non-conflicting batch duplicates' do
    plain_job = job(id: 'plain', state: :queued)
    inserts = described_class::EnqueueMany::InsertBuilder.new(
      namespace:,
      existing_rows: { queue_entries: [] },
      queued_jobs: [plain_job],
      batch: nil
    ).build
    expect(inserts.fetch(:idempotency_keys)).to eq([])
    expect(inserts.fetch(:uniqueness_keys)).to eq([])
    keyed_job = job(id: 'keyed', state: :queued, idempotency_key: 'idem-key', uniqueness_key: 'uniq-key', uniqueness_scope: :active)
    keyed_inserts = described_class::EnqueueMany::InsertBuilder.new(
      namespace:,
      existing_rows: { queue_entries: [] },
      queued_jobs: [keyed_job],
      batch: nil
    ).build
    expect(keyed_inserts.fetch(:idempotency_keys).length).to eq(1)
    expect(keyed_inserts.fetch(:uniqueness_keys).length).to eq(1)

    non_conflicting = job(id: 'job-2', state: :submission, uniqueness_key: 'uniq-1')
    accepted_job = job(id: 'job-1', state: :queued, uniqueness_key: 'uniq-1', uniqueness_scope: :queued)
    expect do
      described_class::EnqueueMany::DuplicateBatchGuard.new(job: non_conflicting, accepted_jobs: [accepted_job], now:).validate
    end.not_to raise_error
  end

  it 'covers recovery and expiry skip branches' do
    queued_job = job(id: 'job-queued', state: :queued)
    running_job = job(id: 'job-running', state: :running, expires_at: now - 1)
    rows = {
      jobs: [job_row(queued_job), job_row(running_job)],
      queue_entries: [queue_entry_row(queued_job)],
      reservations: [],
      policy_state: []
    }

    expired = described_class::ExpireJobs.new(store:, request: { now: }, operation_name: :expire_jobs).call(context: context(rows:))
    expect(expired.value).to eq([])
  end

  it 'expires queued jobs and reports expired reservations' do
    expired_queued_job = job(id: 'job-1', state: :queued, expires_at: now - 1)
    reserve_context = context(
      rows: {
        jobs: [job_row(expired_queued_job)],
        queue_entries: [queue_entry_row(expired_queued_job)],
        reservations: [],
        policy_state: []
      }
    )

    expire_jobs = described_class::ExpireJobs.new(store:, request: { now: }, operation_name: :expire_jobs)
    expire_reservations = described_class::ExpireReservations.new(store:, request: { now: }, operation_name: :expire_reservations)

    expect(expire_jobs.call(context: reserve_context).value.map(&:state)).to eq([:failed])
    expect(expire_reservations.call(context: reserve_context).value.map(&:state)).to eq([:failed])
  end

  it 'builds bulk mutation reports and unsupported operations' do
    report = helper_class.new(store:, request: {}).send(
      :report_for,
      action: :retry_jobs,
      job_ids: ['job-1'],
      now:
    ) do |job_id, _changed_jobs, skipped_jobs|
      skipped_jobs << { job_id:, reason: :not_found, state: nil }
    end
    expect(report.skipped_jobs).to eq([{ job_id: 'job-1', reason: :not_found, state: nil }])
    expect(report.action).to eq(:retry_jobs)

    expect(described_class::EnqueueWorkflow).to be < Karya::Internal::DurableQueueStore::Operation
    expect(described_class::WorkflowSnapshot).to be < Karya::Internal::DurableQueueStore::Operation
    expect do
      described_class::Unsupported.new(store:, request: {}, operation_name: :missing).call(context: context(rows: empty_rows))
    end.to raise_error(NotImplementedError, /:missing/)
  end

  it 'skips ineligible dead-letter discards' do
    queued_job = job(id: 'job-1', state: :queued)
    report = described_class::DiscardDeadLetterJobs.new(
      store:,
      request: { job_ids: ['job-1'], now: },
      operation_name: :discard_dead_letter_jobs
    ).call(context: context(rows: { jobs: [job_row(queued_job)], queue_entries: [], reservations: [] }))

    expect(report.value.skipped_jobs).to eq([{ job_id: 'job-1', reason: :ineligible_state, state: :queued }])
  end

  it 'covers workflow interaction, control, and query validation branches' do
    event_definition = Karya::Workflow.define(:events) do
      step :wait, handler: :wait, wait_for_event: :invoice_event
    end
    event_rows = workflow_enqueue_rows(
      definition: event_definition,
      jobs_by_step_id: { wait: job(id: 'job-wait', state: :submission, handler: :wait) },
      batch_id: :event_batch
    )
    _rows_after_event, event_result = run_operation(
      described_class::DeliverWorkflowEvent,
      rows: event_rows,
      request: { batch_id: :event_batch, event: :invoice_event, payload: { 'ok' => true }, now: },
      operation_name: :deliver_workflow_event
    )
    expect(event_result.value.action).to eq(:deliver_workflow_event)
    _history_rows, history_result = run_operation(
      described_class::WorkflowHistory,
      rows: event_rows,
      request: { batch_id: :event_batch, now: },
      operation_name: :workflow_history
    )
    expect(history_result.value.batch_id).to eq('event_batch')

    plain_definition = Karya::Workflow.define(:plain) do
      step :plain, handler: :plain
    end
    plain_rows = workflow_enqueue_rows(
      definition: plain_definition,
      jobs_by_step_id: { plain: job(id: 'job-plain', state: :submission, handler: :plain) },
      batch_id: :plain_batch
    )
    expect do
      run_operation(
        described_class::ApproveWorkflowCheckpoints,
        rows: plain_rows,
        request: { batch_id: :plain_batch, step_ids: [:plain], now: },
        operation_name: :approve_workflow_checkpoints
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /not an approval checkpoint/)
    expect do
      run_operation(
        described_class::QueryWorkflow,
        rows: plain_rows,
        request: { batch_id: :plain_batch, query: :unsupported, now: },
        operation_name: :query_workflow
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /unsupported workflow query/)

    terminal_rows = plain_rows
    terminal_rows, reservation_result = run_operation(
      described_class::Reserve,
      rows: terminal_rows,
      request: { queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: },
      operation_name: :reserve
    )
    reservation_token = reservation_result.value.token
    terminal_rows, = run_operation(
      described_class::StartExecution,
      rows: terminal_rows,
      request: { reservation_token:, now: now + 1 },
      operation_name: :start_execution
    )
    _terminal_rows, = run_operation(
      described_class::CompleteExecution,
      rows: terminal_rows,
      request: { reservation_token:, now: now + 2 },
      operation_name: :complete_execution
    )
  end

  it 'covers workflow approval and support helper branches' do
    approval_definition = Karya::Workflow.define(:approval) do
      step :approve, handler: :approve, wait_for_approval: :approve_signal
    end
    approval_rows = workflow_enqueue_rows(
      definition: approval_definition,
      jobs_by_step_id: { approve: job(id: 'job-approve', state: :submission, handler: :approve) },
      batch_id: :approval_batch
    )
    approved_rows, _approved_result = run_operation(
      described_class::ApproveWorkflowCheckpoints,
      rows: approval_rows,
      request: { batch_id: :approval_batch, step_ids: [:approve], now: },
      operation_name: :approve_workflow_checkpoints
    )
    expect do
      run_operation(
        described_class::ApproveWorkflowCheckpoints,
        rows: approved_rows,
        request: { batch_id: :approval_batch, step_ids: [:approve], now: now + 1 },
        operation_name: :approve_workflow_checkpoints
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /not awaiting approval/)
    helper = helper_class.new(store:, request: {})
    expect(helper.send(:workflow_operation?, :workflow_snapshot)).to be(true)
    expect(helper.send(:workflow_operation?, :enqueue)).to be(false)
  end

  it 'covers workflow runtime helper branches directly' do
    helper = helper_class.new(store:, request: {})
    approval_definition = Karya::Workflow.define(:approval) do
      step :approve, handler: :approve, wait_for_approval: :approve_signal
      step :signal_step, handler: :signal_step, wait_for_signal: :ready_signal, depends_on: :approve
      step :event_step, handler: :event_step, wait_for_event: :ready_event, depends_on: :signal_step
    end
    rows = workflow_enqueue_rows(
      definition: approval_definition,
      jobs_by_step_id: {
        approve: job(id: 'job-approve', state: :submission, handler: :approve),
        signal_step: job(id: 'job-signal', state: :submission, handler: :signal_step),
        event_step: job(id: 'job-event', state: :submission, handler: :event_step)
      },
      batch_id: :helper_batch
    )
    described_class::WorkflowSnapshot.new(
      store:,
      request: { batch_id: :helper_batch, now: },
      operation_name: :workflow_snapshot
    ).call(context: context(rows:)).value
    interaction_row = Karya::Internal::DurableQueueStore::WorkflowInteractionRecord.new(
      namespace:,
      batch_id: 'helper_batch',
      sequence: 1,
      interaction: Karya::Workflow::InteractionSnapshot.new(kind: :signal, name: 'ready_signal', payload: {}, received_at: now)
    ).to_h
    approval_signal_row = Karya::Internal::DurableQueueStore::WorkflowInteractionRecord.new(
      namespace:,
      batch_id: 'helper_batch',
      sequence: 2,
      interaction: Karya::Workflow::InteractionSnapshot.new(kind: :signal, name: 'approve_signal', payload: {}, received_at: now)
    ).to_h
    rows_with_interaction = rows.merge(workflow_interactions: [interaction_row, approval_signal_row])
    registration = helper.send(:registration_for_batch, rows_with_interaction, 'helper_batch')
    expect(helper.send(:workflow_approval_satisfied?, rows_with_interaction, registration, 'helper_batch',
                       job(id: 'job-approve', state: :queued, handler: :approve))).to be(true)
    expect(helper.send(:workflow_interaction_satisfied?, rows_with_interaction, registration, 'helper_batch',
                       job(id: 'job-signal', state: :queued, handler: :signal_step))).to be(true)

    child_relationship_row = policy_row(
      policy_kind: 'workflow_child_relationship',
      scope_kind: 'parent_step',
      scope_value: 'helper_batch:approve',
      state_payload: Karya::Internal::DurableQueueStore::PolicyStateRecord.stringify_payload(
        parent_workflow_id: 'approval',
        parent_workflow_family: 'approval',
        parent_workflow_version: 'v1',
        parent_batch_id: 'helper_batch',
        parent_step_id: 'approve',
        parent_job_id: 'job-approve',
        child_workflow_id: 'child',
        child_workflow_family: 'child',
        child_workflow_version: 'v1',
        child_batch_id: 'child_batch'
      )
    )
    child_batch_relationship_row = child_relationship_row.merge(scope_kind: 'child_batch', scope_value: 'child_batch')
    child_rows = workflow_enqueue_rows(
      definition: Karya::Workflow.define(:child) { step :capture, handler: :capture },
      jobs_by_step_id: { capture: job(id: 'job-capture-child', state: :submission, handler: :capture) },
      batch_id: :child_batch
    )
    child_batch = child_rows.fetch(:workflow_batches).first.merge(state: 'succeeded')
    parent_snapshot = helper.send(
      :workflow_parent_snapshot,
      child_rows.merge(policy_state: [child_relationship_row, child_batch_relationship_row], workflow_batches: [child_batch]),
      'child_batch',
      now,
      cache: {},
      visiting: {}
    )
    expect(helper.send(:child_relationship_for_parent_step, { policy_state: [child_relationship_row] }, 'helper_batch',
                       'approve').child_batch_id).to eq('child_batch')
    expect(parent_snapshot.child_state).to eq(:pending)

    expect do
      helper.send(:workflow_control_job_ids, registration, [:missing])
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /unknown workflow step/)
    expect do
      helper.send(:workflow_batch_from_rows, rows.merge(workflow_batches: []), 'helper_batch')
    end.to raise_error(Karya::Workflow::UnknownBatchError, /helper_batch/)
    interaction_requirements = helper.send(
      :workflow_step_id_rows,
      definition: approval_definition,
      step_job_ids: registration.step_job_ids,
      binding: Struct.new(:compensation_jobs_by_step_id).new({})
    ).fetch(:interaction_requirements_by_job_id).values
    expect(interaction_requirements).to include({ 'kind' => 'signal', 'name' => 'ready_signal' }, { 'kind' => 'event', 'name' => 'ready_event' })
    expect do
      helper.send(:normalize_workflow_step_ids, 'no-array')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /step_ids must be an Array/)
    expect do
      helper.send(:normalize_workflow_step_ids, [])
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /must not be empty/)
    expect do
      helper.send(:normalize_workflow_step_ids, %i[approve approve])
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /duplicate workflow step/)
    expect do
      helper.send(:validate_workflow_enqueue_jobs, rows.merge(namespace:), [Object.new], now)
    end.to raise_error(Karya::InvalidEnqueueError, /jobs entries must be Karya::Job/)
    expect do
      helper.send(:validate_workflow_enqueue_jobs, rows.merge(namespace:), [job(id: 'job-bad', state: :queued, handler: :bad)], now)
    end.to raise_error(Karya::InvalidEnqueueError, /:submission/)
    expect do
      helper.send(:validate_workflow_enqueue_jobs, rows.merge(namespace:), [job(id: 'job-approve', state: :submission, handler: :approve)], now)
    end.to raise_error(Karya::DuplicateJobError, /job-approve/)
    expect do
      helper.send(
        :validate_workflow_enqueue_jobs,
        empty_rows.merge(namespace:),
        [
          job(id: 'dup-job', state: :submission, handler: :approve),
          job(id: 'dup-job', state: :submission, handler: :approve)
        ],
        now
      )
    end.to raise_error(Karya::DuplicateJobError, /dup-job/)
    uniqueness_evaluator = instance_double(Karya::Internal::DurableQueueStore::UniquenessEvaluator)
    allow(Karya::Internal::DurableQueueStore::UniquenessEvaluator).to receive(:new).and_return(uniqueness_evaluator)
    allow(uniqueness_evaluator).to receive(:decision_for).and_return(nil)
    allow(uniqueness_evaluator).to receive(:raise_duplicate_enqueue_error)
    expect do
      helper.send(
        :validate_workflow_enqueue_jobs,
        empty_rows.merge(namespace:),
        [
          job(id: 'dup-stubbed', state: :submission, handler: :approve),
          job(id: 'dup-stubbed', state: :submission, handler: :approve)
        ],
        now
      )
    end.to raise_error(Karya::DuplicateJobError, /dup-stubbed/)
    expect(helper.send(:workflow_child_satisfied?, rows, registration, job(id: 'job-approve', state: :queued, handler: :approve), now)).to be(true)
    paused_rows = rows.merge(
      policy_state: [
        policy_row(
          policy_kind: 'workflow_pause',
          scope_kind: 'workflow',
          scope_value: 'helper_batch',
          state_payload: Karya::Internal::DurableQueueStore::PolicyStateRecord.stringify_payload(requested_at: now)
        )
      ]
    )
    expect(helper.send(:workflow_dependencies_satisfied?, paused_rows, job(id: 'job-approve', state: :queued, handler: :approve), now:)).to be(false)
    expect(helper.send(:workflow_dependencies_satisfied?, rows, job(id: 'job-signal', state: :queued, handler: :signal_step), now:)).to be(false)
    expect(helper.send(:workflow_dependencies_satisfied?, rows, job(id: 'job-approve', state: :queued, handler: :approve), now:)).to be(false)
    expect(helper.send(:workflow_interaction_satisfied?, rows, registration, 'helper_batch',
                       job(id: 'job-signal', state: :queued, handler: :signal_step))).to be(false)
    rejected_rows = rows.merge(
      policy_state: [
        policy_row(
          policy_kind: 'workflow_approval_decision',
          scope_kind: 'job',
          scope_value: 'job-approve',
          state_payload: { state: :rejected, decided_at: now, reason: 'manual' }
        )
      ]
    )
    expect(helper.send(:workflow_approval_satisfied?, rejected_rows, registration, 'helper_batch',
                       job(id: 'job-approve', state: :queued, handler: :approve))).to be(false)
    child_blocked_definition = Karya::Workflow.define(:child_blocked) do
      step :child, handler: :child, child_workflow: :child_flow
    end
    child_blocked_rows = workflow_enqueue_rows(
      definition: child_blocked_definition,
      jobs_by_step_id: { child: job(id: 'job-child-blocked', state: :submission, handler: :child) },
      batch_id: :child_blocked_batch
    )
    child_blocked_registration = helper.send(:registration_for_batch, child_blocked_rows, 'child_blocked_batch')
    expect(helper.send(:workflow_child_satisfied?, child_blocked_rows, child_blocked_registration,
                       job(id: 'job-child-blocked', state: :queued, handler: :child), now)).to be(false)
    recovered_rows = Karya::Internal::DurableQueueStore::Operations::RecoveredRowsApplier.new(
      namespace:,
      rows: { namespace:, jobs: [job_row(job(id: 'job-1', state: :queued))], queue_entries: [], reservations: [] },
      jobs: [job(id: 'job-1', state: :failed)]
    ).apply
    expect(Karya::Internal::DurableQueueStore::Operations::JobRow.new(row: recovered_rows.fetch(:jobs).first).to_job.state).to eq(:failed)
    expect(
      helper.send(
        :workflow_history_rows_for_job,
        empty_rows,
        namespace:,
        replacement_job: job(id: 'missing-history', state: :queued, handler: :plain),
        from_state: nil
      )
    ).to eq([])
  end
end
