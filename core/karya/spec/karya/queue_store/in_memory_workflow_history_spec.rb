# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::InMemory do
  subject(:store) { described_class.new(token_generator:) }

  let(:token_sequence) { (1..20).map { |index| "lease-#{index}" }.each }
  let(:token_generator) { -> { token_sequence.next } }
  let(:created_at) { Time.utc(2026, 4, 29, 12, 0, 0) }

  def workflow_job(step_id, handler: step_id, retry_policy: nil)
    Karya::Job.new(
      id: "job-#{step_id}",
      queue: :billing,
      handler:,
      state: :submission,
      created_at:,
      retry_policy:
    )
  end

  def workflow_history(batch_id, now_offset)
    store.workflow_history(batch_id:, now: created_at + now_offset)
  end

  describe '#workflow_history' do
    it 'exposes workflow history as a first-class inspection surface' do
      definition = Karya::Workflow.define(:single_step) { step :root, handler: :root }
      store.enqueue_workflow(
        definition:,
        jobs_by_step_id: { root: workflow_job(:root) },
        batch_id: :batch_one,
        now: created_at + 1
      )

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.complete_execution(reservation_token: reservation.token, now: created_at + 4)

      history = workflow_history(:batch_one, 5)

      expect(history.workflow_id).to eq('single_step')
      expect(history.entries.map(&:action)).to eq(%w[workflow_registered queued reserved running succeeded])
      expect(history.entries.map(&:kind)).to eq(%i[workflow step step step step])
      expect(history.entries.last.details).to eq('from_state' => 'running')
    end

    it 'raises for non-workflow batches' do
      store.enqueue_many(jobs: [workflow_job(:root)], batch_id: :plain_batch, now: created_at + 1)

      expect do
        workflow_history(:plain_batch, 2)
      end.to raise_error(Karya::Workflow::InvalidExecutionError, 'batch "plain_batch" is not a workflow batch')
    end

    it 'records interaction and control history separately from current-state interaction snapshots' do
      signal_definition = Karya::Workflow.define(:signal_flow) do
        step :review, handler: :review, wait_for_signal: :manager_approved
      end
      approval_definition = Karya::Workflow.define(:approval_flow) do
        step :review, handler: :review, wait_for_approval: :manager_approved
      end
      store.enqueue_workflow(
        definition: signal_definition,
        jobs_by_step_id: { review: workflow_job(:review_signal, handler: :review) },
        batch_id: :batch_one,
        now: created_at + 1
      )
      store.enqueue_workflow(
        definition: approval_definition,
        jobs_by_step_id: { review: workflow_job(:review_approval, handler: :review) },
        batch_id: :batch_two,
        now: created_at + 1
      )

      store.pause_workflow(batch_id: :batch_one, now: created_at + 2)
      store.resume_workflow(batch_id: :batch_one, now: created_at + 3)
      store.deliver_workflow_signal(batch_id: :batch_one, signal: :manager_approved, payload: { 'source' => 'ops' }, now: created_at + 4)
      store.approve_workflow_checkpoints(batch_id: :batch_two, step_ids: [:review], now: created_at + 5)

      history = workflow_history(:batch_one, 6)
      approval_history = workflow_history(:batch_two, 6)

      expect(history.entries.map(&:action)).to include('pause_requested', 'resumed', 'signal_delivered')
      expect(approval_history.entries.map(&:action)).to include('approval_approved')
      signal_entry = history.entries.find { |entry| entry.action == 'signal_delivered' }
      expect(signal_entry.details).to eq('name' => 'manager_approved', 'payload' => { 'source' => 'ops' })
    end

    it 'records workflow-step recovery controls and rollback boundaries' do
      definition = Karya::Workflow.define(:recoverable) do
        step :root, handler: :root, compensate_with: :undo_root
      end
      store.enqueue_workflow(
        definition:,
        jobs_by_step_id: { root: workflow_job(:root) },
        compensation_jobs_by_step_id: { root: workflow_job(:root, handler: :undo_root) },
        batch_id: :batch_one,
        now: created_at + 1
      )

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(reservation_token: reservation.token, now: created_at + 4, failure_classification: :error)
      store.dead_letter_workflow_steps(batch_id: :batch_one, step_ids: [:root], now: created_at + 5, reason: 'operator isolate')
      store.rollback_workflow(batch_id: :batch_one, now: created_at + 6, reason: 'operator rollback')

      replay_definition = Karya::Workflow.define(:replayable) do
        step :root, handler: :root
      end
      store.enqueue_workflow(
        definition: replay_definition,
        jobs_by_step_id: { root: workflow_job(:root_two, handler: :root) },
        batch_id: :batch_two,
        now: created_at + 7
      )
      replay_reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 8)
      store.start_execution(reservation_token: replay_reservation.token, now: created_at + 9)
      store.fail_execution(reservation_token: replay_reservation.token, now: created_at + 10, failure_classification: :error)
      store.dead_letter_workflow_steps(batch_id: :batch_two, step_ids: [:root], now: created_at + 11, reason: 'operator isolate')
      store.replay_workflow_steps(batch_id: :batch_two, step_ids: [:root], now: created_at + 12)

      history = workflow_history(:batch_one, 13)
      replay_history = workflow_history(:batch_two, 13)

      expect(history.entries.map(&:action)).to include(
        'failed',
        'dead_letter_workflow_steps',
        'dead_letter',
        'rollback_requested'
      )
      expect(replay_history.entries.map(&:action)).to include('replay_workflow_steps', 'queued')
      rollback_entry = history.entries.find { |entry| entry.action == 'rollback_requested' }
      expect(rollback_entry.details.fetch('reason')).to eq('operator rollback')
      expect(rollback_entry.details.fetch('rollback_batch_created')).to be(false)
      expect(history.entries.map(&:action)).to include('rollback_noop_boundary')
    end

    it 'records the failed transition before retry_pending workflow recovery' do
      retry_policy = Karya::RetryPolicy.new(max_attempts: 2, base_delay: 5, multiplier: 2)
      definition = Karya::Workflow.define(:retriable) do
        step :root, handler: :root
      end
      store.enqueue_workflow(
        definition:,
        jobs_by_step_id: { root: workflow_job(:root, retry_policy:) },
        batch_id: :batch_one,
        now: created_at + 1
      )

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        retry_policy:,
        failure_classification: :error
      )

      history = workflow_history(:batch_one, 5)
      actions = history.entries.map(&:action)
      failed_index = actions.index('failed')
      retry_pending_index = actions.index('retry_pending')

      expect(failed_index).not_to be_nil
      expect(retry_pending_index).not_to be_nil
      expect(failed_index).to be < retry_pending_index
      expect(history.entries.fetch(retry_pending_index).details).to eq('from_state' => 'failed')
    end

    it 'records child workflow enqueue and sync history with child batch linkage' do
      parent_definition = Karya::Workflow.define(:parent) do
        step :child, handler: :child, child_workflow: :payment
      end
      child_definition = Karya::Workflow.define(:payment) do
        step :authorize, handler: :authorize
      end
      store.enqueue_workflow(
        definition: parent_definition,
        jobs_by_step_id: { child: workflow_job(:child) },
        batch_id: :parent_batch,
        now: created_at + 1
      )
      store.enqueue_child_workflow(
        parent_batch_id: :parent_batch,
        parent_step_id: :child,
        definition: child_definition,
        jobs_by_step_id: { authorize: workflow_job(:authorize) },
        batch_id: :child_batch,
        now: created_at + 2
      )
      child_reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 3)
      store.start_execution(reservation_token: child_reservation.token, now: created_at + 4)
      store.fail_execution(reservation_token: child_reservation.token, now: created_at + 5, failure_classification: :error)
      store.sync_child_workflows(parent_batch_id: :parent_batch, now: created_at + 6)

      history = workflow_history(:parent_batch, 7)

      enqueue_entry = history.entries.find { |entry| entry.action == 'child_workflow_enqueued' }
      sync_entry = history.entries.find { |entry| entry.action == 'child_workflow_sync_failed' }

      expect(enqueue_entry.child_batch_id).to eq('child_batch')
      expect(sync_entry.child_batch_id).to eq('child_batch')
      expect(sync_entry.details).to eq('child_state' => 'failed')
    end

    it 'does not append duplicate child sync history when the parent job is already terminal' do
      parent_definition = Karya::Workflow.define(:parent) do
        step :child, handler: :child, child_workflow: :payment
      end
      child_definition = Karya::Workflow.define(:payment) do
        step :authorize, handler: :authorize
      end
      store.enqueue_workflow(
        definition: parent_definition,
        jobs_by_step_id: { child: workflow_job(:child) },
        batch_id: :parent_batch,
        now: created_at + 1
      )
      store.enqueue_child_workflow(
        parent_batch_id: :parent_batch,
        parent_step_id: :child,
        definition: child_definition,
        jobs_by_step_id: { authorize: workflow_job(:authorize) },
        batch_id: :child_batch,
        now: created_at + 2
      )
      child_reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 3)
      store.start_execution(reservation_token: child_reservation.token, now: created_at + 4)
      store.fail_execution(reservation_token: child_reservation.token, now: created_at + 5, failure_classification: :error)

      store.sync_child_workflows(parent_batch_id: :parent_batch, now: created_at + 6)
      first_history = workflow_history(:parent_batch, 7)
      expect(first_history.entries.count { |entry| entry.action == 'child_workflow_sync_failed' }).to eq(1)

      store.sync_child_workflows(parent_batch_id: :parent_batch, now: created_at + 8)
      second_history = workflow_history(:parent_batch, 9)
      expect(second_history.entries.count { |entry| entry.action == 'child_workflow_sync_failed' }).to eq(1)
    end
  end
end
