# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Karya::Internal::DurableQueueStore::Operations::PauseWorkflow do
  include_context 'with durable queue-store operations spec support'

  it 'rejects terminal workflow control requests' do
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
        request: { batch_id: :plain_batch, now: now + 3 },
        operation_name: :pause_workflow
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /terminal and cannot be controlled/)

    expect do
      run_operation(
        Karya::Internal::DurableQueueStore::Operations::ResumeWorkflow,
        rows: terminal_rows,
        request: { batch_id: :plain_batch, now: now + 3 },
        operation_name: :resume_workflow
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /terminal and cannot be controlled/)
  end

  it 'persists workflow pause and clears it on resume' do
    definition = Karya::Workflow.define(:plain) do
      step :capture, handler: :capture
    end
    plain_rows = workflow_enqueue_rows(
      definition:,
      jobs_by_step_id: { capture: job(id: 'job-capture', state: :submission, handler: :capture) },
      batch_id: :plain_batch
    )

    paused_rows, pause_result = run_operation(
      described_class,
      rows: plain_rows,
      request: { batch_id: :plain_batch, now: now + 3 },
      operation_name: :pause_workflow
    )
    expect(pause_result.mutation_plan.inserts.fetch(:policy_state).first.fetch(:policy_kind)).to eq('workflow_pause')

    _resume_rows, resume_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::ResumeWorkflow,
      rows: plain_rows,
      request: { batch_id: :plain_batch, now: now + 3 },
      operation_name: :resume_workflow
    )
    expect(resume_result.mutation_plan.deletes.fetch(:policy_state, [])).to eq([])

    _resumed_rows, resumed_result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::ResumeWorkflow,
      rows: paused_rows,
      request: { batch_id: :plain_batch, now: now + 4 },
      operation_name: :resume_workflow
    )
    expect(resumed_result.mutation_plan.deletes.fetch(:policy_state).size).to eq(1)
  end
end
