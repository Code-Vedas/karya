# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Karya::Internal::DurableQueueStore::Operations::WorkflowStepBulkOperation do
  include_context 'with durable queue-store operations spec support'

  let(:approval_definition) do
    Karya::Workflow.define(:approval) do
      step :approve, handler: :approve, wait_for_approval: :approve_signal
    end
  end

  let(:child_definition) do
    Karya::Workflow.define(:payments) do
      step :capture, handler: :capture
    end
  end

  let(:parent_definition) do
    Karya::Workflow.define(:parent) do
      step :child, handler: :child, child_workflow: :payments
    end
  end

  def failed_workflow_rows
    base_rows = workflow_enqueue_rows(
      definition: approval_definition,
      jobs_by_step_id: { approve: job(id: 'job-approve', state: :submission, handler: :approve, queue: 'billing') },
      batch_id: :failed_batch
    )
    base_rows.merge(
      jobs: [job_row(job(id: 'job-approve', state: :failed, handler: :approve, queue: 'billing'))],
      workflow_steps: [base_rows.fetch(:workflow_steps).first.merge(state: 'failed')],
      queue_entries: []
    )
  end

  def parent_rows
    base_rows = workflow_enqueue_rows(
      definition: parent_definition,
      jobs_by_step_id: { child: job(id: 'job-child', state: :submission, handler: :child) },
      batch_id: :parent_batch
    )
    base_rows.merge(
      jobs: [job_row(job(id: 'job-child', state: :queued, handler: :child))],
      workflow_steps: [base_rows.fetch(:workflow_steps).first.merge(state: 'queued')]
    )
  end

  def cancelled_sync_rows
    child_rows = child_workflow_rows
    cancelled_capture_rows = child_rows.merge(
      jobs: child_rows.fetch(:jobs).map do |row|
        row.fetch(:job_id) == 'job-capture' ? job_row(job(id: 'job-capture', state: :cancelled, handler: :capture, queue: 'billing')) : row
      end,
      workflow_steps: child_rows.fetch(:workflow_steps).map do |row|
        row.fetch(:job_id) == 'job-capture' ? row.merge(state: 'cancelled') : row
      end
    )
    cancelled_capture_rows.merge(
      jobs: cancelled_capture_rows.fetch(:jobs).map do |row|
        row.fetch(:job_id) == 'job-child' ? job_row(job(id: 'job-child', state: :succeeded, handler: :child)) : row
      end,
      workflow_steps: cancelled_capture_rows.fetch(:workflow_steps).map do |row|
        row.fetch(:job_id) == 'job-child' ? row.merge(state: 'succeeded') : row
      end
    )
  end

  def child_workflow_rows
    rows = workflow_enqueue_rows(
      definition: parent_definition,
      jobs_by_step_id: { child: job(id: 'job-child', state: :submission, handler: :child) },
      batch_id: :parent_batch
    )
    child_rows, = run_operation(
      Karya::Internal::DurableQueueStore::Operations::EnqueueChildWorkflow,
      rows:,
      request: {
        definition: child_definition,
        jobs_by_step_id: { capture: job(id: 'job-capture', state: :submission, handler: :capture) },
        parent_batch_id: :parent_batch,
        parent_step_id: :child,
        batch_id: :child_batch,
        now:
      },
      operation_name: :enqueue_child_workflow
    )
    child_rows
  end

  it 'covers retry and dead-letter workflow step transitions' do
    failed_rows = failed_workflow_rows.merge(
      jobs: [
        job_row(job(id: 'job-approve', state: :failed, handler: :approve, uniqueness_key: 'uniq-1', uniqueness_scope: :active)),
        job_row(job(id: 'blocker', state: :queued, handler: :approve, uniqueness_key: 'uniq-1', uniqueness_scope: :active))
      ],
      queue_entries: [queue_entry_row(job(id: 'blocker', state: :queued, handler: :approve, uniqueness_key: 'uniq-1', uniqueness_scope: :active))]
    )
    _retry_rows, retry_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::RetryWorkflowSteps,
      rows: failed_rows,
      request: { batch_id: :failed_batch, step_ids: [:approve], now: now + 1 },
      operation_name: :retry_workflow_steps
    )
    expect(retry_result.value.skipped_jobs).to eq([{ job_id: 'job-approve', reason: :uniqueness_conflict, state: :failed }])

    retry_pending_rows = failed_workflow_rows.merge(
      jobs: [job_row(job(id: 'job-approve', state: :retry_pending, handler: :approve, next_retry_at: now + 60))],
      queue_entries: []
    )
    _retried_rows, retried_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::RetryWorkflowSteps,
      rows: retry_pending_rows,
      request: { batch_id: :failed_batch, step_ids: [:approve], now: now + 1 },
      operation_name: :retry_workflow_steps
    )
    expect(retried_result.value.changed_jobs.first).to have_attributes(state: :queued)

    _retry_skip_rows, retry_skip_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::RetryWorkflowSteps,
      rows: parent_rows,
      request: { batch_id: :parent_batch, step_ids: [:child], now: now + 1 },
      operation_name: :retry_workflow_steps
    )
    expect(retry_skip_result.value.skipped_jobs).to eq([{ job_id: 'job-child', reason: :ineligible_state, state: :queued }])

    _dead_rows, dead_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::DeadLetterWorkflowSteps,
      rows: cancelled_sync_rows,
      request: { batch_id: :parent_batch, step_ids: [:child], reason: 'manual', now: now + 1 },
      operation_name: :dead_letter_workflow_steps
    )
    expect(dead_result.value.skipped_jobs).to eq([{ job_id: 'job-child', reason: :ineligible_state, state: :succeeded }])

    runnable_dead_rows = parent_rows.merge(
      jobs: [job_row(job(id: 'job-child', state: :failed, handler: :child))],
      queue_entries: []
    )
    dead_rows_after, dead_success_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::DeadLetterWorkflowSteps,
      rows: runnable_dead_rows,
      request: { batch_id: :parent_batch, step_ids: [:child], reason: 'manual', now: now + 1 },
      operation_name: :dead_letter_workflow_steps
    )
    expect(dead_success_result.value.changed_jobs.map(&:id)).to eq(['job-child'])
    expect(dead_rows_after.fetch(:jobs).first.fetch(:state)).to eq('dead_letter')
  end

  it 'covers replay and retry-dead-letter workflow step transitions' do
    dead_letter_rows = failed_workflow_rows.merge(
      jobs: [
        job_row(job(id: 'job-approve', state: :dead_letter, handler: :approve, uniqueness_key: 'uniq-1', uniqueness_scope: :active)),
        job_row(job(id: 'blocker', state: :queued, handler: :approve, uniqueness_key: 'uniq-1', uniqueness_scope: :active))
      ],
      queue_entries: [queue_entry_row(job(id: 'blocker', state: :queued, handler: :approve, uniqueness_key: 'uniq-1', uniqueness_scope: :active))]
    )
    _replay_rows, replay_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::ReplayWorkflowSteps,
      rows: dead_letter_rows,
      request: { batch_id: :failed_batch, step_ids: [:approve], now: now + 1 },
      operation_name: :replay_workflow_steps
    )
    expect(replay_result.value.skipped_jobs).to eq([{ job_id: 'job-approve', reason: :uniqueness_conflict, state: :dead_letter }])

    _replay_skip_rows, replay_skip_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::ReplayWorkflowSteps,
      rows: parent_rows,
      request: { batch_id: :parent_batch, step_ids: [:child], now: now + 1 },
      operation_name: :replay_workflow_steps
    )
    expect(replay_skip_result.value.skipped_jobs).to eq([{ job_id: 'job-child', reason: :ineligible_state, state: :queued }])

    replayable_rows = failed_workflow_rows.merge(
      jobs: [job_row(job(id: 'job-approve', state: :dead_letter, handler: :approve))],
      queue_entries: []
    )
    replayed_rows, replay_success_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::ReplayWorkflowSteps,
      rows: replayable_rows,
      request: { batch_id: :failed_batch, step_ids: [:approve], now: now + 1 },
      operation_name: :replay_workflow_steps
    )
    expect(replay_success_result.value.changed_jobs.map(&:id)).to eq(['job-approve'])
    expect(replayed_rows.fetch(:jobs).first.fetch(:state)).to eq('queued')

    _retry_dead_rows, retry_dead_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::RetryDeadLetterWorkflowSteps,
      rows: dead_letter_rows,
      request: { batch_id: :failed_batch, step_ids: [:approve], next_retry_at: now + 60, now: now + 1 },
      operation_name: :retry_dead_letter_workflow_steps
    )
    expect(retry_dead_result.value.skipped_jobs).to eq([{ job_id: 'job-approve', reason: :uniqueness_conflict, state: :dead_letter }])

    _retry_dead_skip_rows, retry_dead_skip_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::RetryDeadLetterWorkflowSteps,
      rows: parent_rows,
      request: { batch_id: :parent_batch, step_ids: [:child], next_retry_at: now + 60, now: now + 1 },
      operation_name: :retry_dead_letter_workflow_steps
    )
    expect(retry_dead_skip_result.value.skipped_jobs).to eq([{ job_id: 'job-child', reason: :ineligible_state, state: :queued }])
    retriable_dead_rows = failed_workflow_rows.merge(
      jobs: [job_row(job(id: 'job-approve', state: :dead_letter, handler: :approve))],
      queue_entries: []
    )
    retried_dead_rows, retry_dead_success_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::RetryDeadLetterWorkflowSteps,
      rows: retriable_dead_rows,
      request: { batch_id: :failed_batch, step_ids: [:approve], next_retry_at: now + 60, now: now + 1 },
      operation_name: :retry_dead_letter_workflow_steps
    )
    expect(retry_dead_success_result.value.changed_jobs.map(&:id)).to eq(['job-approve'])
    expect(retried_dead_rows.fetch(:jobs).first.fetch(:state)).to eq('retry_pending')
  end

  it 'covers discard workflow step transitions' do
    discardable_rows = failed_workflow_rows.merge(
      jobs: [job_row(job(id: 'job-approve', state: :dead_letter, handler: :approve))],
      workflow_steps: [failed_workflow_rows.fetch(:workflow_steps).first.merge(state: 'dead_letter')],
      queue_entries: []
    )
    discarded_rows, discard_success_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::DiscardWorkflowSteps,
      rows: discardable_rows,
      request: { batch_id: :failed_batch, step_ids: [:approve], now: now + 1 },
      operation_name: :discard_workflow_steps
    )
    expect(discard_success_result.value.changed_jobs.map(&:id)).to eq(['job-approve'])
    expect(discarded_rows.fetch(:jobs).first.fetch(:state)).to eq('cancelled')

    _discard_rows, discard_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::DiscardWorkflowSteps,
      rows: parent_rows,
      request: { batch_id: :parent_batch, step_ids: [:child], now: now + 1 },
      operation_name: :discard_workflow_steps
    )
    expect(discard_result.value.skipped_jobs).to eq([{ job_id: 'job-child', reason: :ineligible_state, state: :queued }])
  end
end
