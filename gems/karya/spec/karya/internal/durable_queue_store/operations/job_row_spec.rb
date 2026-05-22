# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::Operations::JobRow do
  include_context 'with durable queue-store operations spec support'

  it 'decodes durable job rows into runtime jobs' do
    retry_pending_job = job(
      id: 'job-1',
      state: :retry_pending,
      next_retry_at: now + 30,
      retry_policy: Karya::RetryPolicy.new(max_attempts: 3, base_delay: 1, multiplier: 1),
      concurrency_scope: Karya::Backpressure::Scope.new(kind: :queue, value: 'billing'),
      rate_limit_scope: Karya::Backpressure::Scope.new(kind: :handler, value: 'ProcessInvoice')
    )

    decoded = described_class.new(row: job_row(retry_pending_job)).to_job

    expect(decoded.id).to eq('job-1')
    expect(decoded.state).to eq(:retry_pending)
    expect(decoded.next_retry_at).to eq(now + 30)
    expect(decoded.enqueued_at).to eq(retry_pending_job.enqueued_at)
    expect(decoded.retry_policy).to be_a(Karya::RetryPolicy)
    expect(decoded.concurrency_scope.key).to eq('queue:billing')
    expect(decoded.rate_limit_scope.key).to eq('handler:ProcessInvoice')
  end

  it 'indexes durable rows for repeated job and reservation lookups' do
    queued_job = job(id: 'job-1', state: :queued)
    other_job = job(id: 'job-2', state: :queued)
    rows = {
      jobs: [job_row(queued_job), job_row(other_job)],
      reservations: [reservation_row(job: queued_job, token: 'token-1', phase: :reserved)],
      queue_entries: [queue_entry_row(queued_job), queue_entry_row(other_job, insertion_sequence: 2)]
    }

    index = Karya::Internal::DurableQueueStore::Operations::RowIndex.new(rows:)

    expect(index.jobs_by_id.keys).to contain_exactly('job-1', 'job-2')
    expect(index.queue_entries_for('job-1').length).to eq(1)
    expect(index.reservations_for('job-1').length).to eq(1)
    expect(index.reservations_for('job-1', worker_id: 'worker-2')).to be_empty
    expect(index.reservation_to_job_map.fetch('token-1')).to have_attributes(id: 'job-1')
  end

  it 'rebuilds durable row groups around one job transition' do
    queued_job = job(id: 'job-1', state: :queued, idempotency_key: 'idem-1', uniqueness_key: 'uniq-1', uniqueness_scope: :active)
    rows = {
      namespace: 'spec',
      jobs: [job_row(queued_job)],
      reservations: [reservation_row(job: queued_job, token: 'token-1', phase: :reserved)],
      queue_entries: [queue_entry_row(queued_job)]
    }

    runtime_rows = Karya::Internal::DurableQueueStore::Operations::JobRuntimeRows.new(namespace: 'spec', rows:)

    expect(runtime_rows.job_for('job-1')).to have_attributes(id: 'job-1')
    expect(
      runtime_rows.deletes_for(job_id: 'job-1', delete_queue_entries: true, delete_reservations: true).keys
    ).to contain_exactly(:queue_entries, :reservations)
    expect(runtime_rows.enqueue_insert_groups_for(queued_job).keys).to include(:jobs, :queue_entries, :idempotency_keys, :uniqueness_keys)
    expect(runtime_rows.enqueue_insert_groups_for(job(id: 'job-2', state: :queued)).keys).to contain_exactly(:jobs, :queue_entries)
    expect(runtime_rows.enqueue_insert_groups_for(job(id: 'job-3', state: :submission)).keys).to eq([:jobs])
    expect(runtime_rows.append_enqueued(queued_job).fetch(:jobs).length).to eq(2)
    expect(runtime_rows.replace(job_id: 'job-1', replacement_job: queued_job.transition_to(:cancelled, updated_at: now)).fetch(:queue_entries)).to be_empty
  end

  it 'decodes persisted policy-state payloads through a row wrapper' do
    row = policy_row(policy_kind: 'workflow_pause', scope_kind: 'workflow', scope_value: 'batch-1', state_payload: { 'requested_at' => now.iso8601 })

    payload = Karya::Internal::DurableQueueStore::Operations::PolicyStateRow.new(row:).payload

    expect(payload.fetch('requested_at')).to eq(now.iso8601)
    expect(Karya::Internal::DurableQueueStore::Operations::PolicyStateRow.new(row: nil).payload(default: nil)).to be_nil
    expect(Karya::Internal::DurableQueueStore::Operations::PolicyStateRow.new(row: { state_payload: nil }).payload(default: nil)).to be_nil
  end

  it 'counts active reservations for one concurrency scope' do
    scoped_job = job(
      id: 'job-1',
      state: :reserved,
      concurrency_scope: Karya::Backpressure::Scope.new(kind: :queue, value: 'billing')
    )
    rows = {
      namespace: 'spec',
      jobs: [job_row(scoped_job)],
      reservations: [reservation_row(job: scoped_job, token: 'token-1', phase: :reserved)],
      queue_entries: []
    }

    count = Karya::Internal::DurableQueueStore::Operations::ActiveConcurrencyCounter.new(
      rows:,
      scope_key: 'queue:billing'
    ).count

    expect(count).to eq(1)
  end

  it 'derives scope keys and next insertion sequence through dedicated objects' do
    scoped_job = job(
      id: 'job-1',
      state: :queued,
      concurrency_scope: Karya::Backpressure::Scope.new(kind: :queue, value: 'billing')
    )
    queue_entries = [queue_entry_row(scoped_job, insertion_sequence: 3)]

    scope_keys = Karya::Internal::DurableQueueStore::Operations::ScopeKeySet.new(
      job: scoped_job,
      explicit_scope: scoped_job.concurrency_scope
    ).to_a
    next_sequence = Karya::Internal::DurableQueueStore::Operations::QueueEntrySequence.new(
      queue_entries:,
      queue: 'billing'
    ).next_value

    expect(scope_keys).to eq(['queue:billing', 'handler:ProcessInvoice'])
    expect(next_sequence).to eq(4)
  end

  it 'reconstructs workflow batches from durable workflow rows' do
    rows = {
      workflow_batches: [workflow_batch_row(batch_id: 'batch-1')],
      workflow_steps: [
        workflow_step_row(batch_id: 'batch-1', step_id: 'step-2', job_id: 'job-2').merge(step_sequence: 2),
        workflow_step_row(batch_id: 'batch-1', step_id: 'step-1', job_id: 'job-1').merge(step_sequence: 1)
      ]
    }

    batch = Karya::Internal::DurableQueueStore::Operations::WorkflowBatchBuilder.new(rows:, batch_id: 'batch-1').build

    expect(batch.id).to eq('batch-1')
    expect(batch.job_ids).to eq(%w[job-1 job-2])
  end
end
