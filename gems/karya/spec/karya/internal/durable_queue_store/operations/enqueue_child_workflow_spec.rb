# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::Operations::EnqueueChildWorkflow do
  include_context 'with durable queue-store operations spec support'

  it 'rejects invalid child workflow definitions and parent step mismatches' do
    parent_definition = Karya::Workflow.define(:parent) do
      step :child, handler: :child, child_workflow: :payments
    end
    parent_rows = workflow_enqueue_rows(
      definition: parent_definition,
      jobs_by_step_id: { child: job(id: 'job-child', state: :submission, handler: :child) },
      batch_id: :parent_batch
    )
    mismatch_definition = Karya::Workflow.define(:other_child) do
      step :capture, handler: :capture
    end

    expect do
      run_operation(
        described_class,
        rows: parent_rows,
        request: {
          definition: mismatch_definition,
          jobs_by_step_id: { capture: job(id: 'job-capture', state: :submission, handler: :capture) },
          parent_batch_id: :parent_batch,
          parent_step_id: :child,
          batch_id: :child_batch,
          now:
        },
        operation_name: :enqueue_child_workflow
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /does not match parent step/)

    expect do
      run_operation(
        described_class,
        rows: parent_rows,
        request: {
          definition: Object.new,
          jobs_by_step_id: {},
          parent_batch_id: :parent_batch,
          parent_step_id: :child,
          batch_id: :child_batch,
          now:
        },
        operation_name: :enqueue_child_workflow
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /Karya::Workflow::Definition/)
  end

  it 'rejects duplicate registrations and invalid parent child states' do
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
      described_class,
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

    expect do
      run_operation(
        described_class,
        rows: child_rows,
        request: {
          definition: child_definition,
          jobs_by_step_id: { capture: job(id: 'job-capture-2', state: :submission, handler: :capture) },
          parent_batch_id: :parent_batch,
          parent_step_id: :child,
          batch_id: :child_batch_two,
          now:
        },
        operation_name: :enqueue_child_workflow
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /already registered/)

    expect do
      run_operation(
        described_class,
        rows: parent_rows.merge(jobs: [job_row(job(id: 'job-child', state: :running, handler: :child))]),
        request: {
          definition: child_definition,
          jobs_by_step_id: { capture: job(id: 'job-capture-4', state: :submission, handler: :capture) },
          parent_batch_id: :parent_batch,
          parent_step_id: :child,
          batch_id: :child_batch_four,
          now:
        },
        operation_name: :enqueue_child_workflow
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /must be queued/)
  end

  it 'rejects non-child parent steps and invalid child batch identifiers' do
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
    non_child_definition = Karya::Workflow.define(:non_child_parent) do
      step :plain, handler: :plain
    end
    non_child_rows = workflow_enqueue_rows(
      definition: non_child_definition,
      jobs_by_step_id: { plain: job(id: 'job-plain-parent', state: :submission, handler: :plain) },
      batch_id: :non_child_parent
    )

    expect do
      run_operation(
        described_class,
        rows: non_child_rows,
        request: {
          definition: child_definition,
          jobs_by_step_id: { capture: job(id: 'job-capture-3', state: :submission, handler: :capture) },
          parent_batch_id: :non_child_parent,
          parent_step_id: :plain,
          batch_id: :child_batch_three,
          now:
        },
        operation_name: :enqueue_child_workflow
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /not a child workflow step/)

    expect do
      run_operation(
        described_class,
        rows: parent_rows,
        request: {
          definition: child_definition,
          jobs_by_step_id: { capture: job(id: 'job-capture-5', state: :submission, handler: :capture) },
          parent_batch_id: :parent_batch,
          parent_step_id: :child,
          batch_id: :parent_batch,
          now:
        },
        operation_name: :enqueue_child_workflow
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /must differ from parent batch id/)

    expect do
      run_operation(
        described_class,
        rows: parent_rows.merge(workflow_batches: parent_rows.fetch(:workflow_batches) + [workflow_batch_row(batch_id: 'dup_child_batch')]),
        request: {
          definition: child_definition,
          jobs_by_step_id: { capture: job(id: 'job-capture-6', state: :submission, handler: :capture) },
          parent_batch_id: :parent_batch,
          parent_step_id: :child,
          batch_id: :dup_child_batch,
          now:
        },
        operation_name: :enqueue_child_workflow
      )
    end.to raise_error(Karya::Workflow::DuplicateBatchError, /dup_child_batch/)
  end
end
