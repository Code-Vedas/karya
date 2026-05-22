# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'fileutils'
require 'tmpdir'

RSpec.describe Karya::QueueStore::SQLite do
  def submission_job(id:, created_at:, queue: 'billing', handler: 'ProcessInvoice', arguments: {}, **attributes)
    Karya::Job.new(
      id:,
      queue:,
      handler:,
      arguments:,
      state: :submission,
      created_at:,
      **attributes
    )
  end

  def workflow_job(step_id, created_at:, handler: step_id, queue: 'billing', arguments: {}, priority: 0, uniqueness_key: nil, uniqueness_scope: nil)
    Karya::Job.new(
      id: "job-#{step_id}",
      queue:,
      handler:,
      arguments:,
      priority:,
      uniqueness_key:,
      uniqueness_scope:,
      state: :submission,
      created_at:
    )
  end

  def compensation_job(step_id, created_at:, handler: :"undo_#{step_id}", queue: 'rollback', arguments: {}, priority: 0, uniqueness_key: nil,
                       uniqueness_scope: nil)
    Karya::Job.new(
      id: "rollback-job-#{step_id}",
      queue:,
      handler:,
      arguments:,
      priority:,
      uniqueness_key:,
      uniqueness_scope:,
      state: :submission,
      created_at:
    )
  end

  def reserve_work(store, now_offset, handler_names: nil, queue: 'billing')
    store.reserve(
      queue:,
      handler_names:,
      worker_id: "worker-#{now_offset}",
      lease_duration: 60,
      now: created_at + now_offset
    )
  end

  def run_successfully(store, reservation, start_offset:, complete_offset:)
    store.start_execution(reservation_token: reservation.token, now: created_at + start_offset)
    store.complete_execution(reservation_token: reservation.token, now: created_at + complete_offset)
  end

  def rollback_batch_id(batch_id)
    "__karya_workflow_rollback_v1__#{batch_id.to_s.unpack1('H*')}"
  end

  def build_failed_rollback_workflow(store)
    definition = Karya::Workflow.define(:rollback_chain) do
      step :first, handler: :first, compensate_with: :undo_first
      step :second, handler: :second, depends_on: :first, compensate_with: :undo_second
      step :third, handler: :third, depends_on: :second
    end

    store.enqueue_workflow(
      definition:,
      jobs_by_step_id: {
        first: workflow_job(:first, created_at:, handler: :first),
        second: workflow_job(:second, created_at:, handler: :second),
        third: workflow_job(:third, created_at:, handler: :third)
      },
      compensation_jobs_by_step_id: {
        first: compensation_job(:first, created_at:, handler: :undo_first),
        second: compensation_job(:second, created_at:, handler: :undo_second)
      },
      batch_id: :batch_one,
      now: created_at + 1
    )
    run_successfully(store, reserve_work(store, 2, handler_names: ['first']), start_offset: 3, complete_offset: 4)
    run_successfully(store, reserve_work(store, 5, handler_names: ['second']), start_offset: 6, complete_offset: 7)
    third = reserve_work(store, 8, handler_names: ['third'])
    store.start_execution(reservation_token: third.token, now: created_at + 9)
    store.fail_execution(reservation_token: third.token, now: created_at + 10, failure_classification: :error)

    retry_report = store.retry_workflow_steps(batch_id: :batch_one, step_ids: [:third], now: created_at + 11)
    retried = reserve_work(store, 12, handler_names: ['third'])
    store.start_execution(reservation_token: retried.token, now: created_at + 13)
    store.fail_execution(reservation_token: retried.token, now: created_at + 14, failure_classification: :error)
    rollback_report = store.rollback_workflow(batch_id: :batch_one, now: created_at + 15, reason: 'operator rollback')
    rollback_snapshot = store.workflow_snapshot(batch_id: :batch_one, now: created_at + 16).rollback

    [retry_report, rollback_report, rollback_snapshot]
  end

  let(:tmpdir) { Dir.mktmpdir }
  let(:database_path) { File.join(tmpdir, 'queue.sqlite3') }
  let(:store) { described_class.new(url: "sqlite:///#{database_path}", namespace: 'spec') }
  let(:created_at) { Time.utc(2026, 5, 23, 12, 0, 0) }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  it 'enqueues one job into durable rows and exposes uniqueness reads from persisted data' do
    job = submission_job(
      id: 'job-1',
      created_at:,
      idempotency_key: 'submit-1',
      uniqueness_key: 'billing:account-1',
      uniqueness_scope: :active
    )

    queued_job = store.enqueue(job:, now: created_at + 1)
    snapshot = store.uniqueness_snapshot(now: created_at + 2)

    expect(queued_job.state).to eq(:queued)
    expect(snapshot[:idempotency_keys]).to include('submit-1' => include(job_id: 'job-1', state: :queued))
    expect(snapshot[:uniqueness_keys]).to include(
      'billing:account-1' => contain_exactly(include(job_id: 'job-1', blocked_incoming_scopes: include(:active)))
    )

    table_names = Karya::Internal::DurableQueueStoreCatalog.table_names
    expect(store.connection.get_first_value("SELECT COUNT(*) FROM #{table_names.fetch(:jobs)}")).to eq(1)
    expect(store.connection.get_first_value("SELECT COUNT(*) FROM #{table_names.fetch(:queue_entries)}")).to eq(1)
    expect(store.connection.get_first_value("SELECT COUNT(*) FROM #{table_names.fetch(:idempotency_keys)}")).to eq(1)
    expect(store.connection.get_first_value("SELECT COUNT(*) FROM #{table_names.fetch(:uniqueness_keys)}")).to eq(1)
  end

  it 'rejects duplicate idempotency keys through the persisted enqueue path' do
    store.enqueue(
      job: submission_job(id: 'job-1', created_at:, idempotency_key: 'submit-1'),
      now: created_at + 1
    )

    expect do
      store.enqueue(
        job: submission_job(id: 'job-2', created_at: created_at + 2, idempotency_key: 'submit-1'),
        now: created_at + 3
      )
    end.to raise_error(Karya::DuplicateIdempotencyKeyError, /submit-1/)
  end

  it 'persists queue pause and resume through policy_state rows' do
    paused = store.pause_queue(queue: 'billing', now: created_at + 1)
    table_name = Karya::Internal::DurableQueueStoreCatalog.table_name(:policy_state)

    expect(paused.paused).to be(true)
    expect(paused.changed).to be(true)
    expect(store.connection.get_first_value("SELECT COUNT(*) FROM #{table_name}")).to eq(1)

    paused_again = store.pause_queue(queue: 'billing', now: created_at + 2)
    resumed = store.resume_queue(queue: 'billing', now: created_at + 3)
    resumed_again = store.resume_queue(queue: 'billing', now: created_at + 4)

    expect(paused_again.changed).to be(false)
    expect(resumed.paused).to be(false)
    expect(resumed.changed).to be(true)
    expect(store.connection.get_first_value("SELECT COUNT(*) FROM #{table_name}")).to eq(0)
    expect(resumed_again.changed).to be(false)
  end

  it 'reserves, releases, starts, and completes execution through durable rows' do
    queued_job = store.enqueue(
      job: submission_job(id: 'job-1', created_at:, priority: 1),
      now: created_at + 1
    )
    store.enqueue(
      job: submission_job(id: 'job-2', created_at: created_at + 1, priority: 10),
      now: created_at + 2
    )

    reservation = store.reserve(
      queue: 'billing',
      worker_id: 'worker-1',
      lease_duration: 60,
      now: created_at + 3
    )
    expect(reservation.job_id).to eq('job-2')
    expect(queued_job.enqueued_at).to eq(created_at + 1)

    released_job = store.release(reservation_token: reservation.token, now: created_at + 4)
    expect(released_job.id).to eq('job-2')
    expect(released_job.state).to eq(:queued)
    expect(released_job.enqueued_at).to eq(created_at + 4)

    second_reservation = store.reserve(
      queue: 'billing',
      worker_id: 'worker-1',
      lease_duration: 60,
      now: created_at + 5
    )
    expect(second_reservation.job_id).to eq('job-2')

    running_job = store.start_execution(reservation_token: second_reservation.token, now: created_at + 6)
    expect(running_job.state).to eq(:running)
    expect(running_job.attempt).to eq(1)

    succeeded_job = store.complete_execution(reservation_token: second_reservation.token, now: created_at + 7)
    expect(succeeded_job.state).to eq(:succeeded)

    third_reservation = store.reserve(
      queue: 'billing',
      worker_id: 'worker-1',
      lease_duration: 60,
      now: created_at + 8
    )
    expect(third_reservation.job_id).to eq('job-1')
  end

  it 'moves failed executions into retry_pending and re-reserves them when due' do
    retry_policy = Karya::RetryPolicy.new(max_attempts: 3, base_delay: 5, multiplier: 2)
    store.enqueue(
      job: submission_job(id: 'job-1', created_at:),
      now: created_at + 1
    )

    reservation = store.reserve(
      queue: 'billing',
      worker_id: 'worker-1',
      lease_duration: 60,
      now: created_at + 2
    )
    store.start_execution(reservation_token: reservation.token, now: created_at + 3)

    retried_job = store.fail_execution(
      reservation_token: reservation.token,
      now: created_at + 4,
      retry_policy: retry_policy,
      failure_classification: :timeout
    )

    expect(retried_job.state).to eq(:retry_pending)
    expect(retried_job.next_retry_at).to eq(created_at + 9)
    expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 8)).to be_nil

    reservation = store.reserve(
      queue: 'billing',
      worker_id: 'worker-2',
      lease_duration: 60,
      now: created_at + 9
    )
    expect(reservation.job_id).to eq('job-1')
    expect(store.start_execution(reservation_token: reservation.token, now: created_at + 10).enqueued_at).to eq(created_at + 9)
  end

  it 'supports bulk enqueue, retry, cancel, and dead-letter recovery through durable rows' do
    enqueue_report = store.enqueue_many(
      jobs: [
        submission_job(id: 'job-failed', created_at:),
        submission_job(id: 'job-cancel', created_at: created_at + 1),
        submission_job(id: 'job-dead', created_at: created_at + 2)
      ],
      now: created_at + 3
    )
    expect(enqueue_report.action).to eq(:enqueue_many)
    expect(enqueue_report.changed_jobs.map(&:id)).to eq(%w[job-failed job-cancel job-dead])

    failed_reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 4)
    store.start_execution(reservation_token: failed_reservation.token, now: created_at + 5)
    store.fail_execution(
      reservation_token: failed_reservation.token,
      now: created_at + 6,
      failure_classification: :error
    )

    retry_report = store.retry_jobs(job_ids: ['job-failed'], now: created_at + 7)
    expect(retry_report.action).to eq(:retry_jobs)
    expect(retry_report.changed_jobs.map(&:state)).to eq([:queued])

    cancel_report = store.cancel_jobs(job_ids: ['job-cancel'], now: created_at + 8)
    expect(cancel_report.changed_jobs.map(&:state)).to eq([:cancelled])

    dead_letter_report = store.dead_letter_jobs(job_ids: ['job-dead'], now: created_at + 9, reason: 'manual isolation')
    expect(dead_letter_report.changed_jobs.map(&:state)).to eq([:dead_letter])

    replay_report = store.replay_dead_letter_jobs(job_ids: ['job-dead'], now: created_at + 10)
    expect(replay_report.changed_jobs.map(&:state)).to eq([:queued])

    dead_letter_again = store.dead_letter_jobs(job_ids: ['job-dead'], now: created_at + 11, reason: 'manual isolation')
    expect(dead_letter_again.changed_jobs.map(&:state)).to eq([:dead_letter])

    retry_dead_letter_report = store.retry_dead_letter_jobs(
      job_ids: ['job-dead'],
      now: created_at + 12,
      next_retry_at: created_at + 14
    )
    expect(retry_dead_letter_report.changed_jobs.map(&:state)).to eq([:retry_pending])
    expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 13)&.job_id).not_to eq('job-dead')
    expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 14)&.job_id).to eq('job-dead')
  end

  it 'persists batch membership and reads batch snapshots from durable rows' do
    report = store.enqueue_many(
      jobs: [
        submission_job(id: 'job-batch-1', created_at:),
        submission_job(id: 'job-batch-2', created_at: created_at + 1)
      ],
      now: created_at + 2,
      batch_id: 'invoice-closeout'
    )
    snapshot = store.batch_snapshot(batch_id: ' invoice-closeout ', now: created_at + 3)

    expect(report.changed_jobs.map(&:id)).to eq(%w[job-batch-1 job-batch-2])
    expect(snapshot.batch_id).to eq('invoice-closeout')
    expect(snapshot.job_ids).to eq(%w[job-batch-1 job-batch-2])
    expect(snapshot.total_count).to eq(2)
    expect(snapshot.aggregate_state).to eq(:running)
    expect(snapshot.state_counts).to eq(queued: 2)

    table_names = Karya::Internal::DurableQueueStoreCatalog.table_names
    expect(store.connection.get_first_value("SELECT COUNT(*) FROM #{table_names.fetch(:workflow_batches)}")).to eq(1)
    expect(store.connection.get_first_value("SELECT COUNT(*) FROM #{table_names.fetch(:workflow_steps)}")).to eq(2)
  end

  it 'discards dead-lettered jobs through durable rows' do
    store.enqueue(job: submission_job(id: 'job-1', created_at:), now: created_at + 1)
    store.dead_letter_jobs(job_ids: ['job-1'], now: created_at + 2, reason: 'operator isolated')

    discard_report = store.discard_dead_letter_jobs(job_ids: ['job-1'], now: created_at + 3)

    expect(discard_report.action).to eq(:discard_dead_letter_jobs)
    expect(discard_report.changed_jobs.map(&:state)).to eq([:cancelled])
    expect(store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 4)).to be_nil
  end

  it 'recovers expired reservations and executions through durable rows' do
    store.enqueue(job: submission_job(id: 'job-reserved', created_at:), now: created_at + 1)
    store.enqueue(job: submission_job(id: 'job-running', created_at: created_at + 1), now: created_at + 2)

    store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 2, now: created_at + 3)
    running = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 1, now: created_at + 4)
    store.start_execution(reservation_token: running.token, now: created_at + 4.5)

    report = store.recover_in_flight(now: created_at + 8)

    expect(report.recovered_reserved_jobs.map(&:id)).to eq(['job-reserved'])
    expect(report.recovered_running_jobs.map(&:id)).to eq(['job-running'])
    expect(store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 60, now: created_at + 9)&.job_id).to eq('job-reserved')
    expect(store.reserve(queue: 'billing', worker_id: 'worker-4', lease_duration: 60, now: created_at + 10)&.job_id).to eq('job-running')
  end

  it 'recovers only the requested worker orphan set through durable rows' do
    store.enqueue(job: submission_job(id: 'job-worker-1', created_at:), now: created_at + 1)
    store.enqueue(job: submission_job(id: 'job-worker-2', created_at: created_at + 1), now: created_at + 2)
    store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 3)
    store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 1, now: created_at + 4)

    recovered_jobs = store.recover_orphaned_jobs(worker_id: 'worker-1', now: created_at + 8)

    expect(recovered_jobs.map(&:id)).to eq(['job-worker-1'])
    expect(store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 60, now: created_at + 9)&.job_id).to eq('job-worker-1')
  end

  it 'builds a row-native backpressure snapshot for configured concurrency scopes' do
    scoped_store = described_class.new(
      url: "sqlite:///#{database_path}",
      namespace: 'spec',
      policy_set: Karya::Backpressure::PolicySet.new(
        concurrency: {
          { kind: :queue, value: 'billing' } => { limit: 1 }
        },
        rate_limits: {
          { kind: :tenant, value: 'tenant-7' } => { limit: 1, period: 60 }
        }
      )
    )
    scoped_store.enqueue(
      job: Karya::Job.new(
        id: 'job-1',
        queue: 'billing',
        handler: 'ProcessInvoice',
        arguments: {},
        state: :submission,
        created_at:,
        rate_limit_scope: { kind: :tenant, value: 'tenant-7' }
      ),
      now: created_at + 1
    )
    scoped_store.enqueue(
      job: Karya::Job.new(
        id: 'job-2',
        queue: 'billing',
        handler: 'ProcessInvoice',
        arguments: {},
        state: :submission,
        created_at: created_at + 1,
        rate_limit_scope: { kind: :tenant, value: 'tenant-7' }
      ),
      now: created_at + 2
    )

    scoped_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 3)
    snapshot = scoped_store.backpressure_snapshot(now: created_at + 4)

    expect(snapshot[:captured_at]).to eq(created_at + 4)
    expect(snapshot[:concurrency].fetch('queue:billing')).to include(limit: 1, active_count: 1, blocked_count: 1)
    expect(snapshot[:rate_limits].fetch('tenant:tenant-7')).to include(limit: 1, period: 60, window_count: 1, blocked_count: 1)
  end

  it 'enqueues workflow rows, gates dependent reserve, snapshots progress, and supports workflow queries' do
    definition = Karya::Workflow.define(:snapshot_chain) do
      step :root, handler: :root
      step :child, handler: :child, depends_on: :root
    end

    report = store.enqueue_workflow(
      definition:,
      jobs_by_step_id: {
        root: workflow_job(:root, created_at:, handler: :root),
        child: workflow_job(:child, created_at:, handler: :child)
      },
      batch_id: :batch_one,
      now: created_at + 1
    )

    blocked = store.workflow_snapshot(batch_id: :batch_one, now: created_at + 2)
    initial_state = store.query_workflow(batch_id: :batch_one, query: :state, now: created_at + 3)
    initial_step = store.query_workflow(batch_id: :batch_one, query: 'current-step', now: created_at + 4)
    root = reserve_work(store, 5, handler_names: ['root'])
    run_successfully(store, root, start_offset: 6, complete_offset: 7)
    ready = store.workflow_snapshot(batch_id: :batch_one, now: created_at + 8)
    history = store.workflow_history(batch_id: :batch_one, now: created_at + 9)

    expect(report.action).to eq(:enqueue_many)
    expect(report.changed_jobs.map(&:id)).to eq(%w[job-root job-child])
    expect(blocked.state).to eq(:blocked)
    expect(blocked.step_states).to eq('root' => :queued, 'child' => :queued)
    expect(blocked.fetch_step(:root)).to be_ready
    expect(blocked.fetch_step(:child)).to be_blocked
    expect(initial_state.value).to eq(:blocked)
    expect(initial_step.value).to eq('root')
    expect(ready.fetch_step(:child)).to be_ready
    expect(ready.state).to eq(:running)
    expect(history.entries.map(&:action)).to include('workflow_registered', 'queued', 'succeeded')
    expect(reserve_work(store, 10, handler_names: ['child']).job_id).to eq('job-child')
  end

  it 'supports signals, approvals, pause-resume controls, and preserves workflow interactions in history' do
    definition = Karya::Workflow.define(:approval_gate) do
      step :approve, handler: :approve, wait_for_approval: :manager_approved
    end

    signal_definition = Karya::Workflow.define(:signal_gate) do
      step :approve, handler: :approve_signal, wait_for_approval: :manager_approved
    end

    pause_definition = Karya::Workflow.define(:pause_gate) do
      step :root, handler: :root
      step :approve, handler: :approve_pause, wait_for_approval: :manager_approved, depends_on: :root
    end

    store.enqueue_workflow(
      definition:,
      jobs_by_step_id: { approve: workflow_job(:approve, created_at:, handler: :approve) },
      batch_id: :approval_batch,
      now: created_at + 1
    )
    store.enqueue_workflow(
      definition: signal_definition,
      jobs_by_step_id: { approve: workflow_job(:approve_signal, created_at:, handler: :approve_signal) },
      batch_id: :signal_batch,
      now: created_at + 2
    )
    store.enqueue_workflow(
      definition: pause_definition,
      jobs_by_step_id: {
        root: workflow_job(:root_pause, created_at:, handler: :root),
        approve: workflow_job(:approve_pause, created_at:, handler: :approve_pause)
      },
      batch_id: :pause_batch,
      now: created_at + 3
    )

    approve_report = store.approve_workflow_checkpoints(batch_id: :approval_batch, step_ids: [:approve], now: created_at + 4)
    signal_report = store.deliver_workflow_signal(
      batch_id: :signal_batch,
      signal: :manager_approved,
      payload: { 'approved_by' => 'ops' },
      now: created_at + 5
    )
    pause_root = reserve_work(store, 6, handler_names: ['root'])
    pause_report = store.pause_workflow(batch_id: :pause_batch, now: created_at + 7)
    store.start_execution(reservation_token: pause_root.token, now: created_at + 8)
    store.complete_execution(reservation_token: pause_root.token, now: created_at + 9)
    paused_snapshot = store.workflow_snapshot(batch_id: :pause_batch, now: created_at + 10)
    store.approve_workflow_checkpoints(batch_id: :pause_batch, step_ids: [:approve], now: created_at + 11)
    resume_report = store.resume_workflow(batch_id: :pause_batch, now: created_at + 12)
    signal_history = store.workflow_history(batch_id: :signal_batch, now: created_at + 13)

    expect(approve_report.action).to eq(:approve_workflow_checkpoints)
    expect(signal_report.action).to eq(:deliver_workflow_signal)
    expect(store.workflow_snapshot(batch_id: :approval_batch, now: created_at + 14).fetch_step(:approve).approval_state).to eq(:approved)
    expect(store.workflow_snapshot(batch_id: :signal_batch, now: created_at + 14).fetch_step(:approve).approval_state).to eq(:approved)
    expect(store.workflow_snapshot(batch_id: :signal_batch, now: created_at + 14).signals.map(&:name)).to eq(['manager_approved'])
    expect(pause_report.action).to eq(:pause_workflow)
    expect(paused_snapshot.state).to eq(:paused)
    expect(resume_report.action).to eq(:resume_workflow)
    expect(reserve_work(store, 15, handler_names: ['approve_pause']).job_id).to eq('job-approve_pause')
    expect(signal_history.entries.map(&:action)).to include('signal_delivered', 'approval_approved')
  end

  it 'enqueues child workflows, syncs failed children into parent jobs, and preserves child links in snapshots' do
    parent_definition = Karya::Workflow.define(:parent) do
      step :prepare, handler: :prepare
      step :payment_subflow, handler: :payment_subflow, depends_on: :prepare, child_workflow: :payment
      step :receipt, handler: :receipt, depends_on: :payment_subflow
    end
    child_definition = Karya::Workflow.define(:payment) do
      step :authorize, handler: :authorize
      step :capture, handler: :capture, depends_on: :authorize
    end

    store.enqueue_workflow(
      definition: parent_definition,
      jobs_by_step_id: {
        prepare: workflow_job(:prepare, created_at:, handler: :prepare),
        payment_subflow: workflow_job(:payment_subflow, created_at:, handler: :payment_subflow),
        receipt: workflow_job(:receipt, created_at:, handler: :receipt)
      },
      batch_id: :parent_batch,
      now: created_at + 1
    )
    run_successfully(store, reserve_work(store, 2), start_offset: 3, complete_offset: 4)

    child_report = store.enqueue_child_workflow(
      parent_batch_id: :parent_batch,
      parent_step_id: :payment_subflow,
      definition: child_definition,
      jobs_by_step_id: {
        authorize: workflow_job(:authorize, created_at:, handler: :authorize),
        capture: workflow_job(:capture, created_at:, handler: :capture)
      },
      batch_id: :payment_batch,
      now: created_at + 5
    )
    run_successfully(store, reserve_work(store, 6), start_offset: 7, complete_offset: 8)
    capture = reserve_work(store, 9)
    store.start_execution(reservation_token: capture.token, now: created_at + 10)
    store.fail_execution(reservation_token: capture.token, now: created_at + 11, failure_classification: :error)

    sync_report = store.sync_child_workflows(parent_batch_id: :parent_batch, now: created_at + 12)
    parent_snapshot = store.workflow_snapshot(batch_id: :parent_batch, now: created_at + 13)
    child_snapshot = store.workflow_snapshot(batch_id: :payment_batch, now: created_at + 13)

    expect(child_report.action).to eq(:enqueue_child_workflow)
    expect(sync_report.action).to eq(:sync_child_workflows)
    expect(sync_report.changed_jobs).to contain_exactly(
      have_attributes(id: 'job-payment_subflow', state: :dead_letter)
    )
    expect(parent_snapshot.child_workflow(:payment_subflow)).to have_attributes(child_batch_id: 'payment_batch', child_state: :failed)
    expect(child_snapshot.parent).to have_attributes(parent_batch_id: 'parent_batch', parent_step_id: 'payment_subflow')
    expect(parent_snapshot.state).to eq(:failed)
  end

  it 'rolls back failed workflows through durable rows' do
    retry_report, rollback_report, rollback_snapshot = build_failed_rollback_workflow(store)

    expect(retry_report.changed_jobs.map(&:id)).to eq(['job-third'])
    expect(rollback_report.changed_jobs.map(&:id)).to eq(%w[rollback-job-second rollback-job-first])
    expect(rollback_snapshot).to have_attributes(
      workflow_batch_id: 'batch_one',
      rollback_batch_id: rollback_batch_id('batch_one'),
      compensation_job_ids: %w[rollback-job-second rollback-job-first]
    )
  end

  it 'supports workflow-step lifecycle controls for rollback batches through durable rows' do
    build_failed_rollback_workflow(store)
    dead_letter_report = store.dead_letter_workflow_steps(
      batch_id: rollback_batch_id('batch_one'),
      step_ids: [:first],
      now: created_at + 17,
      reason: 'manual isolate'
    )
    replay_report = store.replay_workflow_steps(batch_id: rollback_batch_id('batch_one'), step_ids: [:first], now: created_at + 18)
    store.dead_letter_workflow_steps(
      batch_id: rollback_batch_id('batch_one'),
      step_ids: [:first],
      now: created_at + 19,
      reason: 'manual isolate again'
    )
    retry_dead_letter_report = store.retry_dead_letter_workflow_steps(
      batch_id: rollback_batch_id('batch_one'),
      step_ids: [:first],
      now: created_at + 20,
      next_retry_at: created_at + 22
    )
    store.dead_letter_workflow_steps(
      batch_id: rollback_batch_id('batch_one'),
      step_ids: [:first],
      now: created_at + 23,
      reason: 'manual isolate third'
    )
    discard_report = store.discard_workflow_steps(batch_id: rollback_batch_id('batch_one'), step_ids: [:first], now: created_at + 24)

    expect(dead_letter_report.action).to eq(:dead_letter_workflow_steps)
    expect(replay_report.changed_jobs.first).to have_attributes(id: 'rollback-job-first', state: :queued)
    expect(retry_dead_letter_report.changed_jobs.first).to have_attributes(id: 'rollback-job-first', state: :retry_pending)
    expect(discard_report.changed_jobs.first).to have_attributes(id: 'rollback-job-first', state: :cancelled)
  end

  it 'blocks reserve when concurrency or rate-limit backpressure is active' do
    scoped_store = described_class.new(
      url: "sqlite:///#{database_path}",
      namespace: 'spec',
      policy_set: Karya::Backpressure::PolicySet.new(
        concurrency: {
          { kind: :queue, value: 'billing' } => { limit: 1 }
        },
        rate_limits: {
          { kind: :tenant, value: 'tenant-7' } => { limit: 1, period: 60 }
        }
      )
    )
    first_job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :submission,
      created_at:,
      rate_limit_scope: { kind: :tenant, value: 'tenant-7' }
    )
    second_job = Karya::Job.new(
      id: 'job-2',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :submission,
      created_at: created_at + 1,
      rate_limit_scope: { kind: :tenant, value: 'tenant-7' }
    )
    scoped_store.enqueue(job: first_job, now: created_at + 1)
    scoped_store.enqueue(job: second_job, now: created_at + 2)

    expect(scoped_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 3)&.job_id).to eq('job-1')
    expect(scoped_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 4)).to be_nil
  end

  it 'persists circuit-breaker failures and blocks later reservations' do
    breaker_store = described_class.new(
      url: "sqlite:///#{database_path}",
      namespace: 'spec',
      circuit_breaker_policy_set: Karya::CircuitBreaker::PolicySet.new(
        policies: {
          'queue:billing' => {
            failure_threshold: 2,
            window: 60,
            cooldown: 10
          }
        }
      )
    )
    breaker_store.enqueue(job: submission_job(id: 'job-1', created_at:), now: created_at + 1)
    breaker_store.enqueue(job: submission_job(id: 'job-2', created_at: created_at + 1), now: created_at + 2)
    breaker_store.enqueue(job: submission_job(id: 'job-3', created_at: created_at + 2), now: created_at + 3)

    first = breaker_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 4)
    breaker_store.start_execution(reservation_token: first.token, now: created_at + 4.5)
    second = breaker_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 5)
    breaker_store.start_execution(reservation_token: second.token, now: created_at + 5.5)

    breaker_store.fail_execution(reservation_token: first.token, now: created_at + 6, failure_classification: :error)
    breaker_store.fail_execution(reservation_token: second.token, now: created_at + 7, failure_classification: :error)

    expect(breaker_store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 30, now: created_at + 8)).to be_nil

    snapshot = breaker_store.reliability_snapshot(now: created_at + 8)
    expect(snapshot[:circuit_breakers].fetch('queue:billing')).to include(
      state: :open,
      failure_count: 2,
      blocked_count: 1,
      cooldown_until: created_at + 17
    )
  end

  it 'reports stuck jobs after running-lease recovery through durable policy rows' do
    reliability_store = described_class.new(
      url: "sqlite:///#{database_path}",
      namespace: 'spec'
    )
    reliability_store.enqueue(job: submission_job(id: 'job-stuck', created_at:), now: created_at + 1)

    reservation = reliability_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 2)
    reliability_store.start_execution(reservation_token: reservation.token, now: created_at + 2.5)

    snapshot = reliability_store.reliability_snapshot(now: created_at + 5)

    expect(snapshot[:stuck_jobs].fetch('job-stuck')).to include(
      job_id: 'job-stuck',
      state: :queued,
      attempt: 1,
      recovery_count: 1,
      last_recovered_at: created_at + 5,
      last_recovery_reason: 'running_lease_expired'
    )
  end

  it 'reopens a half-open breaker when the probe fails' do
    breaker_store = described_class.new(
      url: "sqlite:///#{database_path}",
      namespace: 'spec',
      circuit_breaker_policy_set: Karya::CircuitBreaker::PolicySet.new(
        policies: {
          'queue:billing' => {
            failure_threshold: 1,
            window: 60,
            cooldown: 5
          }
        }
      )
    )
    %w[job-1 job-2 job-3].each_with_index do |job_id, index|
      breaker_store.enqueue(job: submission_job(id: job_id, created_at: created_at + index), now: created_at + index)
    end

    first = breaker_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 1)
    breaker_store.start_execution(reservation_token: first.token, now: created_at + 1.5)
    breaker_store.fail_execution(reservation_token: first.token, now: created_at + 2, failure_classification: :error)

    probe = breaker_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 8)
    expect(probe&.job_id).to eq('job-2')
    breaker_store.start_execution(reservation_token: probe.token, now: created_at + 8.5)
    breaker_store.fail_execution(reservation_token: probe.token, now: created_at + 9, failure_classification: :error)

    expect(breaker_store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 30, now: created_at + 10)).to be_nil
    expect(breaker_store.reliability_snapshot(now: created_at + 10)[:circuit_breakers].fetch('queue:billing')).to include(state: :open)
  end

  it 'closes a half-open breaker when the probe succeeds' do
    breaker_store = described_class.new(
      url: "sqlite:///#{database_path}",
      namespace: 'spec',
      circuit_breaker_policy_set: Karya::CircuitBreaker::PolicySet.new(
        policies: {
          'queue:billing' => {
            failure_threshold: 1,
            window: 60,
            cooldown: 5
          }
        }
      )
    )
    %w[job-1 job-2 job-3].each_with_index do |job_id, index|
      breaker_store.enqueue(job: submission_job(id: job_id, created_at: created_at + index), now: created_at + index)
    end

    first = breaker_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 1)
    breaker_store.start_execution(reservation_token: first.token, now: created_at + 1.5)
    breaker_store.fail_execution(reservation_token: first.token, now: created_at + 2, failure_classification: :error)

    probe = breaker_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 8)
    expect(probe&.job_id).to eq('job-2')
    breaker_store.start_execution(reservation_token: probe.token, now: created_at + 8.5)
    breaker_store.complete_execution(reservation_token: probe.token, now: created_at + 9)

    expect(breaker_store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 30, now: created_at + 10)&.job_id).to eq('job-3')
    expect(breaker_store.reliability_snapshot(now: created_at + 10)[:circuit_breakers].fetch('queue:billing')).to include(
      state: :closed,
      failure_count: 0
    )
  end

  it 'clears stuck-job metadata after a later success' do
    reliability_store = described_class.new(
      url: "sqlite:///#{database_path}",
      namespace: 'spec'
    )
    reliability_store.enqueue(job: submission_job(id: 'job-stuck', created_at:), now: created_at + 1)

    first = reliability_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 2)
    reliability_store.start_execution(reservation_token: first.token, now: created_at + 2.5)
    reliability_store.reliability_snapshot(now: created_at + 5)

    second = reliability_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 6)
    reliability_store.start_execution(reservation_token: second.token, now: created_at + 6.5)
    reliability_store.complete_execution(reservation_token: second.token, now: created_at + 7)

    expect(reliability_store.reliability_snapshot(now: created_at + 8)[:stuck_jobs]).to eq({})
  end

  it 'expires queued and retry-pending jobs from durable rows' do
    retry_policy = Karya::RetryPolicy.new(max_attempts: 3, base_delay: 5, multiplier: 2)
    store.enqueue(
      job: submission_job(id: 'job-expired-queued', created_at:, expires_at: created_at + 4, priority: 1),
      now: created_at + 1
    )
    store.enqueue(
      job: submission_job(id: 'job-expired-retry', created_at: created_at + 1, expires_at: created_at + 7, priority: 10),
      now: created_at + 2
    )

    reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 3)
    store.start_execution(reservation_token: reservation.token, now: created_at + 4)
    store.fail_execution(
      reservation_token: reservation.token,
      now: created_at + 5,
      retry_policy:,
      failure_classification: :timeout
    )

    expired_jobs = store.expire_jobs(now: created_at + 8)

    expect(expired_jobs.map(&:id)).to contain_exactly('job-expired-queued', 'job-expired-retry')
    expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 9)).to be_nil
  end
end
