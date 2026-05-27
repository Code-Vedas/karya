# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Karya::Internal::DurableQueueStore::Operations::EnqueueWorkflow do
  include_context 'with durable queue-store operations spec support'

  it 'rejects invalid definitions and duplicate batches' do
    expect do
      run_operation(
        described_class,
        rows: empty_rows,
        request: { definition: Object.new, jobs_by_step_id: {}, batch_id: :invalid, now: },
        operation_name: :enqueue_workflow
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /Karya::Workflow::Definition/)

    definition = Karya::Workflow.define(:duplicate_batch) do
      step :first, handler: :first
    end
    rows = workflow_enqueue_rows(
      definition:,
      jobs_by_step_id: { first: job(id: 'job-first', state: :submission, handler: :first) },
      batch_id: :dup_batch
    )

    expect do
      run_operation(
        described_class,
        rows:,
        request: {
          definition:,
          jobs_by_step_id: { first: job(id: 'job-first-2', state: :submission, handler: :first) },
          batch_id: :dup_batch,
          now:
        },
        operation_name: :enqueue_workflow
      )
    end.to raise_error(Karya::Workflow::DuplicateBatchError, /dup_batch/)
  end

  it 'persists key rows for keyed workflow jobs' do
    definition = Karya::Workflow.define(:keyed_batch) do
      step :first, handler: :first
    end

    rows = workflow_enqueue_rows(
      definition:,
      jobs_by_step_id: {
        first: job(
          id: 'job-keyed',
          state: :submission,
          handler: :first,
          idempotency_key: 'idem-keyed',
          uniqueness_key: 'uniq-keyed',
          uniqueness_scope: :active
        )
      },
      batch_id: :keyed_batch
    )

    expect(rows.fetch(:idempotency_keys).map { |row| row.fetch(:idempotency_key) }).to eq(['idem-keyed'])
  end
end
