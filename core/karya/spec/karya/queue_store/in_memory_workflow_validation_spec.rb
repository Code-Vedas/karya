# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::InMemory do
  subject(:store) { described_class.new(token_generator:) }

  let(:token_sequence) { (1..80).map { |index| "lease-#{index}" }.each }
  let(:token_generator) { -> { token_sequence.next } }
  let(:created_at) { Time.utc(2026, 4, 24, 12, 0, 0) }

  def workflow_job(step_id, handler: step_id)
    Karya::Job.new(
      id: "job-#{step_id}",
      queue: :billing,
      handler:,
      state: :submission,
      created_at:
    )
  end

  def compensation_job(step_id, handler: :"undo_#{step_id}")
    Karya::Job.new(
      id: "rollback-job-#{step_id}",
      queue: :rollback,
      handler:,
      state: :submission,
      created_at:
    )
  end

  def reserve(now_offset, handler_names: nil, queue: 'billing')
    store.reserve(
      queue:,
      handler_names:,
      worker_id: "worker-#{now_offset}",
      lease_duration: 60,
      now: created_at + now_offset
    )
  end

  def rollback_batch_id(batch_id)
    internal = Karya::QueueStore::InMemory.const_get(:Internal, false)
    workflow_support = internal.const_get(:WorkflowSupport, false)
    workflow_support.const_get(:RollbackBatchId, false).new(batch_id).to_s
  end

  def run_successfully(reservation, start_offset:, complete_offset:)
    store.start_execution(reservation_token: reservation.token, now: created_at + start_offset)
    store.complete_execution(reservation_token: reservation.token, now: created_at + complete_offset)
  end

  def fail_execution(reservation, start_offset:, fail_offset:)
    store.start_execution(reservation_token: reservation.token, now: created_at + start_offset)
    store.fail_execution(reservation_token: reservation.token, now: created_at + fail_offset, failure_classification: :error)
  end

  def retry_later(reservation, start_offset:, fail_offset:, next_retry_offset:)
    retry_policy = Karya::RetryPolicy.new(max_attempts: 3, base_delay: next_retry_offset - fail_offset, multiplier: 1)
    store.start_execution(reservation_token: reservation.token, now: created_at + start_offset)
    store.fail_execution(
      reservation_token: reservation.token,
      now: created_at + fail_offset,
      retry_policy:,
      failure_classification: :error
    )
  end

  def enqueue_invoice_closeout_workflow
    definition = Karya::Workflow.define(:invoice_closeout_validation) do
      step :authorize, handler: :authorize, compensate_with: :undo_authorize
      step :capture, handler: :capture, depends_on: :authorize, compensate_with: :undo_capture
      step :emit_receipt, handler: :emit_receipt, depends_on: :capture
      step :audit, handler: :audit
    end
    store.enqueue_workflow(
      definition:,
      jobs_by_step_id: {
        authorize: workflow_job(:authorize),
        capture: workflow_job(:capture),
        emit_receipt: workflow_job(:emit_receipt),
        audit: workflow_job(:audit)
      },
      compensation_jobs_by_step_id: {
        authorize: compensation_job(:authorize),
        capture: compensation_job(:capture)
      },
      batch_id: :invoice_closeout_batch,
      now: created_at + 1
    )
  end

  def fail_invoice_receipt
    authorize = reserve(2, handler_names: ['authorize'])
    audit = reserve(3, handler_names: ['audit'])
    run_successfully(authorize, start_offset: 4, complete_offset: 5)
    run_successfully(audit, start_offset: 6, complete_offset: 7)
    capture = reserve(8, handler_names: ['capture'])
    run_successfully(capture, start_offset: 9, complete_offset: 10)
    receipt = reserve(11, handler_names: ['emit_receipt'])
    fail_execution(receipt, start_offset: 12, fail_offset: 13)
  end

  def expect_failed_invoice_snapshot
    failed_snapshot = store.workflow_snapshot(batch_id: :invoice_closeout_batch, now: created_at + 14)
    expect(failed_snapshot).to have_attributes(state: :failed, rollback_requested?: false)
    expect(failed_snapshot.step_states).to eq(
      'authorize' => :succeeded,
      'capture' => :succeeded,
      'emit_receipt' => :failed,
      'audit' => :succeeded
    )
    expect(store.batch_snapshot(batch_id: :invoice_closeout_batch, now: created_at + 14).job_ids)
      .to eq(%w[job-authorize job-capture job-emit_receipt job-audit])
  end

  def rollback_invoice_closeout
    rollback = store.rollback_workflow(batch_id: :invoice_closeout_batch, now: created_at + 15, reason: 'operator rollback')
    expect(rollback.changed_jobs.map(&:id)).to eq(%w[rollback-job-capture rollback-job-authorize])
    rollback_snapshot = store.workflow_snapshot(batch_id: :invoice_closeout_batch, now: created_at + 16).rollback
    expect(rollback_snapshot).to have_attributes(
      workflow_batch_id: 'invoice_closeout_batch',
      rollback_batch_id: rollback_batch_id('invoice_closeout_batch'),
      reason: 'operator rollback',
      compensation_job_ids: %w[rollback-job-capture rollback-job-authorize],
      compensation_count: 2
    )
    expect(store.batch_snapshot(batch_id: rollback_batch_id('invoice_closeout_batch'), now: created_at + 16).job_ids)
      .to eq(%w[rollback-job-capture rollback-job-authorize])
  end

  def recover_capture_compensation
    capture_rollback = reserve(17, handler_names: ['undo_capture'], queue: 'rollback')
    expect(capture_rollback.job_id).to eq('rollback-job-capture')
    expect(reserve(18, handler_names: ['undo_authorize'], queue: 'rollback')).to be_nil
    store.start_execution(reservation_token: capture_rollback.token, now: created_at + 19)
    store.dead_letter_jobs(job_ids: ['rollback-job-capture'], now: created_at + 20, reason: 'operator isolated')
    expect(reserve(21, handler_names: ['undo_authorize'], queue: 'rollback')).to be_nil
    store.replay_dead_letter_jobs(job_ids: ['rollback-job-capture'], now: created_at + 22)
    replayed_capture_rollback = reserve(23, handler_names: ['undo_capture'], queue: 'rollback')
    run_successfully(replayed_capture_rollback, start_offset: 24, complete_offset: 25)
  end

  it 'validates recovery, rollback, compensation gating, and compensation job recovery end to end' do
    enqueue_invoice_closeout_workflow
    fail_invoice_receipt
    expect_failed_invoice_snapshot
    rollback_invoice_closeout
    recover_capture_compensation

    authorize_rollback = reserve(26, handler_names: ['undo_authorize'], queue: 'rollback')
    expect(authorize_rollback.job_id).to eq('rollback-job-authorize')
    run_successfully(authorize_rollback, start_offset: 27, complete_offset: 28)
    expect(store.batch_snapshot(batch_id: rollback_batch_id('invoice_closeout_batch'), now: created_at + 29).aggregate_state).to eq(:succeeded)
  end

  it 'keeps workflow and rollback metadata stable across step retry-dead-letter and discard controls' do
    definition = Karya::Workflow.define(:step_control_metadata_validation) do
      step :root, handler: :root, compensate_with: :undo_root
      step :child, handler: :child, depends_on: :root
    end
    store.enqueue_workflow(
      definition:,
      jobs_by_step_id: { root: workflow_job(:root), child: workflow_job(:child) },
      compensation_jobs_by_step_id: { root: compensation_job(:root) },
      batch_id: :batch_one,
      now: created_at + 1
    )
    root = reserve(2, handler_names: ['root'])
    run_successfully(root, start_offset: 3, complete_offset: 4)
    child = reserve(5, handler_names: ['child'])
    fail_execution(child, start_offset: 6, fail_offset: 7)
    store.rollback_workflow(batch_id: :batch_one, now: created_at + 8, reason: 'operator rollback')

    store.dead_letter_workflow_steps(batch_id: :batch_one, step_ids: [:child], now: created_at + 9, reason: 'operator isolated')
    retry_report = store.retry_dead_letter_workflow_steps(
      batch_id: :batch_one,
      step_ids: [:child],
      now: created_at + 10,
      next_retry_at: created_at + 20
    )
    expect(retry_report.changed_jobs.fetch(0)).to have_attributes(id: 'job-child', state: :retry_pending)
    store.dead_letter_workflow_steps(batch_id: :batch_one, step_ids: [:child], now: created_at + 11, reason: 'operator isolated again')
    discard_report = store.discard_workflow_steps(batch_id: :batch_one, step_ids: [:child], now: created_at + 12)

    snapshot = store.workflow_snapshot(batch_id: :batch_one, now: created_at + 13)
    expect(discard_report.changed_jobs.fetch(0)).to have_attributes(id: 'job-child', state: :cancelled)
    expect(snapshot.step_states).to eq('root' => :succeeded, 'child' => :cancelled)
    expect(snapshot.job_ids).to eq(%w[job-root job-child])
    expect(snapshot.rollback).to have_attributes(
      rollback_batch_id: rollback_batch_id('batch_one'),
      compensation_job_ids: ['rollback-job-root']
    )
    expect(store.batch_snapshot(batch_id: :batch_one, now: created_at + 13).job_ids).to eq(%w[job-root job-child])
  end

  it 'leaves leases, retry indexes, and snapshots unchanged after invalid workflow control requests' do
    definition = Karya::Workflow.define(:invalid_control_validation) do
      step :retrying, handler: :retrying
      step :running, handler: :running
    end
    store.enqueue_workflow(
      definition:,
      jobs_by_step_id: {
        retrying: workflow_job(:retrying),
        running: workflow_job(:running)
      },
      batch_id: :batch_one,
      now: created_at + 1
    )
    retrying = reserve(2, handler_names: ['retrying'])
    running = reserve(3, handler_names: ['running'])
    retry_later(retrying, start_offset: 4, fail_offset: 5, next_retry_offset: 20)
    store.start_execution(reservation_token: running.token, now: created_at + 6)
    before_snapshot = store.workflow_snapshot(batch_id: :batch_one, now: created_at + 7)

    expect do
      store.dead_letter_workflow_steps(
        batch_id: :batch_one,
        step_ids: [:running, ' running '],
        now: created_at + 8,
        reason: 'invalid duplicate target'
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'duplicate workflow step "running"')
    expect do
      store.replay_workflow_steps(batch_id: :batch_one, step_ids: [:missing], now: created_at + 9)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'unknown workflow step "missing"')

    after_snapshot = store.workflow_snapshot(batch_id: :batch_one, now: created_at + 10)
    expect(after_snapshot.step_states).to eq(before_snapshot.step_states)
    expect(reserve(19, handler_names: ['retrying'])).to be_nil
    expect(reserve(20, handler_names: ['retrying']).job_id).to eq('job-retrying')
    expect(store.complete_execution(reservation_token: running.token, now: created_at + 21).id).to eq('job-running')
  end
end
