# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::Operations::WorkflowOperationSupport do
  include_context 'with durable queue-store operations spec support'

  let(:helper) { workflow_runtime_helper_class.new(store:, request: { batch_id: :helper_batch, jobs_by_step_id: {}, now: }, operation_name: :enqueue_workflow) }

  it 'builds workflow enqueue rows, history rows, and enqueue results' do
    definition = Karya::Workflow.define(:support) do
      step :approve, handler: :approve, wait_for_approval: :approve_signal
      step :capture, handler: :capture, depends_on: :approve
    end
    queued_jobs = [
      job(id: 'job-approve', state: :submission, handler: :approve),
      job(id: 'job-capture', state: :submission, handler: :capture)
    ]
    binding = Karya::Workflow.send(
      :build_compensated_execution_binding,
      definition:,
      jobs_by_step_id: { approve: queued_jobs[0], capture: queued_jobs[1] },
      batch_id: :helper_batch,
      compensation_jobs_by_step_id: {}
    )
    step_job_ids = Karya::Internal::DurableQueueStore::Operations::WorkflowRegistrationBuilder.step_job_ids_for(definition, queued_jobs)
    registration = Karya::Internal::DurableQueueStore::Operations::WorkflowRegistrationBuilder.new(
      operation: helper,
      definition:,
      binding:,
      queued_jobs:
    ).build
    enqueue_request = Karya::Internal::DurableQueueStore::Operations::WorkflowEnqueueRequest.new(
      namespace:,
      definition:,
      now:,
      batch_id: 'helper_batch',
      rows: empty_rows,
      queued_jobs:,
      registration:
    )
    enqueue_insert_builder = Karya::Internal::DurableQueueStore::Operations::WorkflowEnqueueInsertBuilder.new(
      operation: helper,
      enqueue_request:
    )
    batch_row = enqueue_insert_builder.send(:workflow_batch_row)
    step_rows = enqueue_insert_builder.send(:workflow_step_rows)
    history_rows = enqueue_insert_builder.send(:workflow_history_rows)
    inserts = Karya::Internal::DurableQueueStore::Operations::WorkflowQueueJobInsertBuilder.new(
      namespace:,
      queued_jobs:,
      existing_queue_entries: []
    ).build
    result = Karya::Internal::DurableQueueStore::Operations::WorkflowEnqueueResultBuilder.new(
      now:,
      action: :enqueue_many,
      queued_jobs:,
      inserts:
    ).build

    expect(step_job_ids).to eq('approve' => 'job-approve', 'capture' => 'job-capture')
    expect(registration.step_id_by_job_id).to eq('job-approve' => 'approve', 'job-capture' => 'capture')
    expect(batch_row.fetch(:batch_id)).to eq('helper_batch')
    expect(step_rows.map { |row| row.fetch(:step_id) }).to eq(%w[approve capture])
    expect(history_rows.length).to eq(3)
    expect(inserts.fetch(:jobs).length).to eq(2)
    expect(inserts.fetch(:queue_entries).length).to eq(2)
    expect(result.value.action).to eq(:enqueue_many)
    expect(result.mutation_plan.inserts.fetch(:jobs).length).to eq(2)
  end

  it 'builds workflow runtime targets, control entries, and terminal checks' do
    definition = Karya::Workflow.define(:plain) do
      step :plain, handler: :plain
    end
    rows = workflow_enqueue_rows(
      definition:,
      jobs_by_step_id: { plain: job(id: 'job-plain', state: :submission, handler: :plain) },
      batch_id: :helper_batch
    )
    batch, registration, snapshot = helper.send(:workflow_target, 'helper_batch', rows, now)
    control_entry = Karya::Internal::DurableQueueStore::Operations::WorkflowControlEntryBuilder.new(
      registration:,
      batch_id: 'helper_batch',
      occurred_at: now,
      entry: { kind: :control, action: :paused }
    ).build
    control_row = helper.send(
      :workflow_control_row,
      rows: rows,
      namespace:,
      batch_id: 'helper_batch',
      entry: control_entry
    )
    runtime_rows, recovery = Karya::Internal::DurableQueueStore::Operations::WorkflowRuntimeContextBuilder.new(
      context: context(rows: empty_rows),
      now:,
      host: helper,
      recover: false
    ).call

    expect(batch.id).to eq('helper_batch')
    expect(snapshot.batch_id).to eq('helper_batch')
    expect(control_row.fetch(:batch_id)).to eq('helper_batch')
    expect(runtime_rows.fetch(:namespace)).to eq(namespace)
    expect(recovery).to include(changed: false)
    expect do
      helper.send(:terminal_workflow_control!, Struct.new(:state).new(:succeeded), 'helper_batch', 'pause')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /terminal and cannot pause/)
  end
end
