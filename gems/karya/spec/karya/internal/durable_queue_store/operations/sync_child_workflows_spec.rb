# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Karya::Internal::DurableQueueStore::Operations::SyncChildWorkflows do
  include_context 'with durable queue-store operations spec support'

  def build_child_sync_rows
    child_definition = Karya::Workflow.define(:payments) do
      step :capture, handler: :capture
    end
    parent_definition = Karya::Workflow.define(:parent) do
      step :child, handler: :child, child_workflow: :payments
    end
    parent_rows = workflow_enqueue_rows(
      definition: parent_definition,
      jobs_by_step_id: { child: job(id: 'job-child', state: :submission, handler: :child) },
      batch_id: :parent_batch
    )
    child_rows, = run_operation(
      Karya::Internal::DurableQueueStore::Operations::EnqueueChildWorkflow,
      rows: parent_rows,
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
    [parent_rows, child_rows]
  end

  it 'syncs cancelled and failed child workflows onto the parent job' do
    _parent_rows, child_rows = build_child_sync_rows
    cancelled_sync_rows = child_rows.merge(
      jobs: child_rows.fetch(:jobs).map do |row|
        row.fetch(:job_id) == 'job-capture' ? job_row(job(id: 'job-capture', state: :cancelled, handler: :capture, queue: 'billing')) : row
      end,
      workflow_steps: child_rows.fetch(:workflow_steps).map do |row|
        row.fetch(:job_id) == 'job-capture' ? row.merge(state: 'cancelled') : row
      end
    )
    _synced_rows, cancelled_sync = run_operation(
      described_class,
      rows: cancelled_sync_rows,
      request: { parent_batch_id: :parent_batch, now: now + 1 },
      operation_name: :sync_child_workflows
    )
    expect(cancelled_sync.value.changed_jobs.map(&:state)).to eq([:cancelled])

    failed_sync_rows = child_rows.merge(
      jobs: child_rows.fetch(:jobs).map do |row|
        row.fetch(:job_id) == 'job-capture' ? job_row(job(id: 'job-capture', state: :failed, handler: :capture, queue: 'billing')) : row
      end,
      workflow_steps: child_rows.fetch(:workflow_steps).map do |row|
        row.fetch(:job_id) == 'job-capture' ? row.merge(state: 'failed') : row
      end
    )
    _failed_sync_rows, failed_sync = run_operation(
      described_class,
      rows: failed_sync_rows,
      request: { parent_batch_id: :parent_batch, now: now + 1 },
      operation_name: :sync_child_workflows
    )
    expect(failed_sync.value.changed_jobs.map(&:state)).to eq([:dead_letter])
  end

  it 'skips sync when the parent job is not transitionable for the child state' do
    _parent_rows, child_rows = build_child_sync_rows
    _steady_sync_rows, steady_sync = run_operation(
      described_class,
      rows: child_rows,
      request: { parent_batch_id: :parent_batch, now: now + 1 },
      operation_name: :sync_child_workflows
    )
    expect(steady_sync.value.skipped_jobs).to eq([{ job_id: 'job-child', reason: :ineligible_state, state: :queued }])

    cancelled_sync_rows = child_rows.merge(
      jobs: child_rows.fetch(:jobs).map do |row|
        row.fetch(:job_id) == 'job-capture' ? job_row(job(id: 'job-capture', state: :cancelled, handler: :capture, queue: 'billing')) : row
      end,
      workflow_steps: child_rows.fetch(:workflow_steps).map do |row|
        row.fetch(:job_id) == 'job-capture' ? row.merge(state: 'cancelled') : row
      end
    )
    skipped_sync_rows = cancelled_sync_rows.merge(
      jobs: cancelled_sync_rows.fetch(:jobs).map do |row|
        row.fetch(:job_id) == 'job-child' ? job_row(job(id: 'job-child', state: :succeeded, handler: :child)) : row
      end,
      workflow_steps: cancelled_sync_rows.fetch(:workflow_steps).map do |row|
        row.fetch(:job_id) == 'job-child' ? row.merge(state: 'succeeded') : row
      end
    )
    _skipped_rows, skipped_sync = run_operation(
      described_class,
      rows: skipped_sync_rows,
      request: { parent_batch_id: :parent_batch, now: now + 1 },
      operation_name: :sync_child_workflows
    )
    expect(skipped_sync.value.skipped_jobs).to eq([{ job_id: 'job-child', reason: :ineligible_state, state: :succeeded }])

    failed_sync_rows = child_rows.merge(
      jobs: child_rows.fetch(:jobs).map do |row|
        row.fetch(:job_id) == 'job-capture' ? job_row(job(id: 'job-capture', state: :failed, handler: :capture, queue: 'billing')) : row
      end,
      workflow_steps: child_rows.fetch(:workflow_steps).map do |row|
        case row.fetch(:job_id)
        when 'job-capture'
          row.merge(state: 'failed')
        when 'job-child'
          row.merge(state: 'succeeded')
        else
          row
        end
      end
    ).merge(
      jobs: child_rows.fetch(:jobs).map do |row|
        case row.fetch(:job_id)
        when 'job-capture'
          job_row(job(id: 'job-capture', state: :failed, handler: :capture, queue: 'billing'))
        when 'job-child'
          job_row(job(id: 'job-child', state: :succeeded, handler: :child))
        else
          row
        end
      end
    )
    _failed_skipped_rows, failed_skipped_sync = run_operation(
      described_class,
      rows: failed_sync_rows,
      request: { parent_batch_id: :parent_batch, now: now + 1 },
      operation_name: :sync_child_workflows
    )
    expect(failed_skipped_sync.value.skipped_jobs).to eq([{ job_id: 'job-child', reason: :ineligible_state, state: :succeeded }])
  end
end
