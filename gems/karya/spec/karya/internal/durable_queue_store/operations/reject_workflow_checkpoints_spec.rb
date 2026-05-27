# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Karya::Internal::DurableQueueStore::Operations::RejectWorkflowCheckpoints do
  include_context 'with durable queue-store operations spec support'

  let(:approval_definition) do
    Karya::Workflow.define(:approval) do
      step :approve, handler: :approve, wait_for_approval: :approve_signal
    end
  end

  let(:approval_rows) do
    workflow_enqueue_rows(
      definition: approval_definition,
      jobs_by_step_id: { approve: job(id: 'job-approve', state: :submission, handler: :approve) },
      batch_id: :approval_batch
    )
  end

  it 'rejects awaiting approval checkpoints and records approval policy state' do
    rejected_rows, rejected_result = run_operation(
      described_class,
      rows: approval_rows,
      request: { batch_id: :approval_batch, step_ids: [:approve], reason: 'nope', now: now + 1 },
      operation_name: :reject_workflow_checkpoints
    )

    expect(rejected_result.value.changed_jobs.first).to have_attributes(id: 'job-approve', state: :cancelled)
    expect(rejected_rows.fetch(:policy_state).map { |row| row.fetch(:policy_kind) }).to include('workflow_approval_decision')
  end

  it 'rejects invalid checkpoint targets and skips ineligible job states' do
    expect do
      run_operation(
        described_class,
        rows: approval_rows,
        request: { batch_id: :approval_batch, step_ids: [:approve], reason: 'nope', now: now + 1 },
        operation_name: :reject_workflow_checkpoints
      )
    end.not_to raise_error

    approved_rows, _approved_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::ApproveWorkflowCheckpoints,
      rows: approval_rows,
      request: { batch_id: :approval_batch, step_ids: [:approve], now: },
      operation_name: :approve_workflow_checkpoints
    )
    expect do
      run_operation(
        described_class,
        rows: approved_rows,
        request: { batch_id: :approval_batch, step_ids: [:approve], reason: 'nope', now: now + 1 },
        operation_name: :reject_workflow_checkpoints
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /not awaiting approval/)

    ineligible_rows = approval_rows.merge(
      jobs: [job_row(job(id: 'job-approve', state: :submission, handler: :approve))],
      workflow_steps: [approval_rows.fetch(:workflow_steps).first.merge(state: 'submission')]
    )
    _rows_after_skip, skip_result = run_operation(
      described_class,
      rows: ineligible_rows,
      request: { batch_id: :approval_batch, step_ids: [:approve], reason: 'nope', now: now + 1 },
      operation_name: :reject_workflow_checkpoints
    )
    expect(skip_result.value.skipped_jobs).to eq([{ job_id: 'job-approve', reason: :ineligible_state, state: :submission }])
  end

  it 'rejects non-approval workflow steps' do
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
        described_class,
        rows: plain_rows,
        request: { batch_id: :plain_batch, step_ids: [:plain], reason: 'nope', now: },
        operation_name: :reject_workflow_checkpoints
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /not an approval checkpoint/)
  end
end
