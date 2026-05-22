# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Karya::Internal::DurableQueueStore::Operations::DeliverWorkflowSignal do
  include_context 'with durable queue-store operations spec support'

  it 'rejects terminal workflow interactions' do
    definition = Karya::Workflow.define(:plain) do
      step :capture, handler: :capture
    end
    plain_rows = workflow_enqueue_rows(
      definition:,
      jobs_by_step_id: { capture: job(id: 'job-capture', state: :submission, handler: :capture) },
      batch_id: :plain_batch
    )
    reserved_rows, reservation_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::Reserve,
      rows: plain_rows,
      request: { queues: ['billing'], worker_id: 'worker-1', lease_duration: 60, now: },
      operation_name: :reserve
    )
    reservation_token = reservation_result.value.token
    running_rows, = run_operation(
      Karya::Internal::DurableQueueStore::Operations::StartExecution,
      rows: reserved_rows,
      request: { reservation_token:, now: now + 1 },
      operation_name: :start_execution
    )
    terminal_rows, = run_operation(
      Karya::Internal::DurableQueueStore::Operations::CompleteExecution,
      rows: running_rows,
      request: { reservation_token:, now: now + 2 },
      operation_name: :complete_execution
    )

    expect do
      run_operation(
        described_class,
        rows: terminal_rows,
        request: { batch_id: :plain_batch, signal: :ignored, payload: {}, now: now + 3 },
        operation_name: :deliver_workflow_signal
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /terminal and cannot receive interactions/)
  end

  it 'rejects unsupported workflow signals' do
    helper = helper_class.new(store:, request: {})

    expect do
      helper.send(
        :validate_workflow_interaction_support!,
        Struct.new(:interaction_supported_keys).new({}.freeze),
        :signal,
        'missing',
        'batch-1'
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /does not support signal/)
  end

  it 'skips auto-approval when the checkpoint was already rejected' do
    approval_definition = Karya::Workflow.define(:approval) do
      step :approve, handler: :approve, wait_for_approval: :approve_signal
    end
    approval_rows = workflow_enqueue_rows(
      definition: approval_definition,
      jobs_by_step_id: { approve: job(id: 'job-approve', state: :submission, handler: :approve) },
      batch_id: :approval_batch
    )
    rejected_rows = approval_rows.merge(
      policy_state: [
        policy_row(
          policy_kind: 'workflow_approval_decision',
          scope_kind: 'job',
          scope_value: 'job-approve',
          state_payload: { state: :rejected, decided_at: now, reason: 'manual' }
        )
      ]
    )

    _rows, result = run_operation(
      described_class,
      rows: rejected_rows,
      request: { batch_id: :approval_batch, signal: :approve_signal, payload: {}, now: now + 1 },
      operation_name: :deliver_workflow_signal
    )

    expect(result.mutation_plan.inserts.fetch(:policy_state, [])).to eq([])
  end

  it 'only auto-approves checkpoints that match the delivered signal' do
    definition = Karya::Workflow.define(:multi_approval) do
      step :approve_one, handler: :approve_one, wait_for_approval: :approve_one_signal
      step :approve_two, handler: :approve_two, wait_for_approval: :approve_two_signal
    end
    rows = workflow_enqueue_rows(
      definition:,
      jobs_by_step_id: {
        approve_one: job(id: 'job-approve-one', state: :submission, handler: :approve_one),
        approve_two: job(id: 'job-approve-two', state: :submission, handler: :approve_two)
      },
      batch_id: :multi_approval_batch
    )

    _updated_rows, result = run_operation(
      described_class,
      rows:,
      request: { batch_id: :multi_approval_batch, signal: :approve_one_signal, payload: {}, now: now + 1 },
      operation_name: :deliver_workflow_signal
    )

    expect(result.mutation_plan.inserts.fetch(:policy_state, []).length).to eq(1)
  end
end
