# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::Operations::RollbackWorkflow do
  include_context 'with durable queue-store operations spec support'

  it 'rejects workflows with active jobs, existing rollbacks, or non-failed state' do
    definition = Karya::Workflow.define(:rollbackable) do
      step :first, handler: :first, compensate_with: :undo_first
      step :second, handler: :second, depends_on: :first
    end
    active_rows = workflow_rows_with_states(
      definition:,
      jobs_by_step_id: {
        first: job(id: 'job-first', state: :submission, handler: :first),
        second: job(id: 'job-second', state: :submission, handler: :second)
      },
      compensation_jobs_by_step_id: { first: job(id: 'rollback-job-first', state: :submission, queue: 'rollback', handler: :undo_first) },
      batch_id: :rollback_batch,
      states_by_job_id: { 'job-first' => :failed, 'job-second' => :running }
    )

    expect do
      run_operation(
        described_class,
        rows: active_rows,
        request: { batch_id: :rollback_batch, reason: 'manual', now: now + 1 },
        operation_name: :rollback_workflow
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /active jobs and cannot be rolled back/)

    expect do
      run_operation(
        described_class,
        rows: active_rows.merge(
          policy_state: [
            policy_row(
              policy_kind: 'workflow_rollback',
              scope_kind: 'workflow',
              scope_value: 'rollback_batch',
              state_payload: Karya::Internal::DurableQueueStore::PolicyStateRecord.stringify_payload(
                batch_id: 'rollback_batch',
                rollback_batch_id: 'rb-1',
                reason: 'again',
                requested_at: now,
                compensation_job_ids: []
              )
            )
          ]
        ),
        request: { batch_id: :rollback_batch, reason: 'manual', now: now + 1 },
        operation_name: :rollback_workflow
      )
    end.to raise_error(Karya::Workflow::DuplicateBatchError, /already has a rollback/)

    parent_rows = workflow_enqueue_rows(
      definition: Karya::Workflow.define(:parent_for_rollback) { step :child, handler: :child, child_workflow: :payments },
      jobs_by_step_id: { child: job(id: 'job-child', state: :submission, handler: :child) },
      batch_id: :parent_batch
    )
    expect do
      run_operation(
        described_class,
        rows: parent_rows,
        request: { batch_id: :parent_batch, reason: 'manual', now: now + 1 },
        operation_name: :rollback_workflow
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /must be failed before rollback/)
  end

  it 'returns a noop rollback when no compensation jobs are registered' do
    noop_definition = Karya::Workflow.define(:rollback_noop) do
      step :done, handler: :done
    end
    noop_rows = workflow_rows_with_states(
      definition: noop_definition,
      jobs_by_step_id: { done: job(id: 'job-done', state: :submission, handler: :done) },
      batch_id: :noop_batch,
      states_by_job_id: { 'job-done' => :failed }
    )

    _noop_rows, noop_rollback = run_operation(
      described_class,
      rows: noop_rows,
      request: { batch_id: :noop_batch, reason: 'manual', now: now + 1 },
      operation_name: :rollback_workflow
    )
    expect(noop_rollback.value.changed_jobs).to eq([])
  end

  it 'builds compensation rollback batches and rejects duplicate rollback batch ids' do
    rollbackable_definition = Karya::Workflow.define(:rollback_real) do
      step :done, handler: :done, compensate_with: :undo_done
      step :failer, handler: :failer, depends_on: :done
    end
    rollbackable_rows = workflow_rows_with_states(
      definition: rollbackable_definition,
      jobs_by_step_id: {
        done: job(id: 'job-done-real', state: :submission, handler: :done),
        failer: job(id: 'job-failer-real', state: :submission, handler: :failer)
      },
      compensation_jobs_by_step_id: { done: job(id: 'job-undo-real', state: :submission, queue: 'rollback', handler: :undo_done) },
      batch_id: :real_rollback_batch,
      states_by_job_id: { 'job-done-real' => :succeeded, 'job-failer-real' => :failed }
    )

    _real_rows, real_rollback = run_operation(
      described_class,
      rows: rollbackable_rows,
      request: { batch_id: :real_rollback_batch, reason: 'manual', now: now + 1 },
      operation_name: :rollback_workflow
    )
    expect(real_rollback.value.changed_jobs.map(&:id)).to eq(['job-undo-real'])

    multi_definition = Karya::Workflow.define(:rollback_multi) do
      step :first, handler: :first, compensate_with: :undo_first
      step :second, handler: :second, compensate_with: :undo_second, depends_on: :first
      step :failer, handler: :failer, depends_on: :second
    end
    multi_rows = workflow_rows_with_states(
      definition: multi_definition,
      jobs_by_step_id: {
        first: job(id: 'job-first-real', state: :submission, handler: :first),
        second: job(id: 'job-second-real', state: :submission, handler: :second),
        failer: job(id: 'job-failer-multi', state: :submission, handler: :failer)
      },
      compensation_jobs_by_step_id: {
        first: job(id: 'job-undo-first-real', state: :submission, queue: 'rollback', handler: :undo_first),
        second: job(id: 'job-undo-second-real', state: :submission, queue: 'rollback', handler: :undo_second)
      },
      batch_id: :multi_rollback_batch,
      states_by_job_id: {
        'job-first-real' => :succeeded,
        'job-second-real' => :succeeded,
        'job-failer-multi' => :failed
      }
    )

    _multi_rows, multi_rollback = run_operation(
      described_class,
      rows: multi_rows,
      request: { batch_id: :multi_rollback_batch, reason: 'manual', now: now + 1 },
      operation_name: :rollback_workflow
    )
    expect(multi_rollback.value.changed_jobs.map(&:id)).to eq(%w[job-undo-second-real job-undo-first-real])

    duplicate_batch_id = "__karya_workflow_rollback_v1__#{'real_rollback_batch'.unpack1('H*')}"
    expect do
      run_operation(
        described_class,
        rows: rollbackable_rows.merge(
          workflow_batches: rollbackable_rows.fetch(:workflow_batches) + [workflow_batch_row(batch_id: duplicate_batch_id)]
        ),
        request: { batch_id: :real_rollback_batch, reason: 'manual', now: now + 1 },
        operation_name: :rollback_workflow
      )
    end.to raise_error(Karya::Workflow::DuplicateBatchError, /already exists/)
  end

  it 'covers rollback helper branches directly' do
    helper = rollback_helper_class.new(store:, request: {}, operation_name: :rollback_workflow)

    expect(helper.send(:rollback_batch_id_for, 'real_rollback_batch')).to start_with('__karya_workflow_rollback_v1__')
    expect(
      helper.send(
        :rollback_runnable_waiting_job?,
        job(id: 'waiting', state: :queued),
        { 'waiting' => ['done'] },
        [job(id: 'done', state: :succeeded)]
      )
    ).to be(true)
    expect(
      helper.send(
        :rollback_runnable_waiting_job?,
        job(id: 'waiting', state: :queued),
        { 'waiting' => ['missing'] },
        []
      )
    ).to be(false)

    snapshot_class = Struct.new(:state, :jobs, :batch_id)
    failed_snapshot = snapshot_class.new(:failed, [job(id: 'done', state: :failed)], 'batch-1')
    expect(helper.send(:rollback_rejection_message, failed_snapshot, {})).to eq('workflow batch "batch-1" can be rolled back')
    expect(helper.send(:rollback_eligible_snapshot?, failed_snapshot, {})).to be(true)

    active_snapshot = snapshot_class.new(:failed, [job(id: 'active', state: :running)], 'batch-2')
    expect do
      helper.send(:validate_rollback_snapshot, active_snapshot, {})
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /active jobs and cannot be rolled back/)
  end
end
