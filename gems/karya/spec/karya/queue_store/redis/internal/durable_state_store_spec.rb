# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::Redis::Internal::DurableStateStore do
  let(:redis) { instance_double(Redis) }
  let(:store) { described_class.new(redis:, namespace: 'spec') }
  let(:job) do
    Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :queued,
      created_at: Time.utc(2026, 5, 23, 12, 0, 0)
    )
  end

  before do
    allow(redis).to receive_messages(hgetall: {}, hvals: [], hset: nil, hdel: nil)
  end

  it 'reads metadata and queue-specific operation rows' do
    allow(redis).to receive(:hgetall).with('spec:queue_store:metadata').and_return(
      'namespace' => 'spec',
      'schema_version' => '3',
      'reservation_token_sequence' => '7'
    )

    expect(store.fetch_metadata(namespace: 'spec')).to eq(
      namespace: 'spec',
      schema_version: 3,
      reservation_token_sequence: 7
    )

    expect(store.fetch_rows_for_operation(operation_name: :enqueue, namespace: 'spec', request: { job: job })).to include(:queue_entries)
    expect(
      store.fetch_rows_for_operation(
        operation_name: :reserve,
        namespace: 'spec',
        request: { queues: %w[billing support] }
      )
    ).to include(:queue_entries, :reservations, :policy_state)
    expect(
      store.fetch_rows_for_operation(
        operation_name: :release,
        namespace: 'spec',
        request: { reservation_token: 'token-1' }
      )
    ).to include(:reservations)
    expect(
      store.fetch_rows_for_operation(
        operation_name: :complete_execution,
        namespace: 'spec',
        request: { reservation_token: 'token-1' }
      )
    ).to include(:reservations, :policy_state)
    expect(store.send(:lock_rows_for_operation, operation_name: :enqueue, namespace: 'spec', request: {}, metadata: {}, rows: {})).to be_nil
  end

  it 'reads uniqueness, full runtime, orphan, pause, and workflow operation branches' do
    expect(
      store.fetch_rows_for_operation(operation_name: :uniqueness_decision, namespace: 'spec', request: {})
    ).to include(:jobs, :reservations, :queue_entries)
    expect(
      store.fetch_rows_for_operation(operation_name: :retry_jobs, namespace: 'spec', request: {})
    ).to include(:jobs, :queue_entries, :reservations, :policy_state)
    expect(
      store.fetch_rows_for_operation(
        operation_name: :recover_orphaned_jobs,
        namespace: 'spec',
        request: { worker_id: 'worker-1' }
      )
    ).to include(:reservations)
    expect(store.fetch_rows_for_operation(operation_name: :pause_queue, namespace: 'spec', request: { queue: 'billing' })).to eq(policy_state: [])

    expect(
      store.fetch_rows_for_operation(operation_name: :enqueue_workflow, namespace: 'spec', request: {})
    ).to include(:workflow_batches, :workflow_steps, :workflow_interactions, :workflow_history, :policy_state)
    expect do
      store.fetch_rows_for_operation(operation_name: :missing, namespace: 'spec', request: {})
    end.to raise_error(NotImplementedError, /:missing/)
  end

  it 'handles enqueue_many without a batch id and reliability rows without a reservation token' do
    expect(
      store.fetch_rows_for_operation(operation_name: :enqueue_many, namespace: 'spec', request: { jobs: [job] })
    ).to include(:queue_entries)
    expect(
      store.fetch_rows_for_operation(operation_name: :reliability_snapshot, namespace: 'spec', request: {})
    ).to include(:policy_state)
  end

  it 'loads workflow batch rows for enqueue_many with a batch id' do
    allow(Karya::Workflow).to receive(:normalize_batch_identifier).with(:batch_id, :batch_one).and_return('batch-one')

    rows = store.fetch_rows_for_operation(
      operation_name: :enqueue_many,
      namespace: 'spec',
      request: { jobs: [job], batch_id: :batch_one }
    )

    expect(rows).to include(:workflow_batches, :workflow_steps)
  end

  it 'loads batch snapshot rows for a normalized batch id and filters unmatched jobs' do
    allow(Karya::Workflow).to receive(:normalize_batch_identifier).with(:batch_id, :batch_one).and_return('batch-one')

    workflow_batch = { namespace: 'spec', batch_id: 'batch-one' }
    workflow_step = { namespace: 'spec', batch_id: 'batch-one', step_id: 'prepare', job_id: 'job-1' }
    job_row = { namespace: 'spec', job_id: 'job-1' }
    other_job_row = { namespace: 'spec', job_id: 'job-2' }

    allow(redis).to receive(:hvals).with('spec:queue_store:rows:workflow_batches').and_return(
      [Base64.strict_encode64(Karya::Internal::DurableQueueStore::PayloadCodec.dump(workflow_batch.transform_keys(&:to_s)))]
    )
    allow(redis).to receive(:hvals).with('spec:queue_store:rows:workflow_steps').and_return(
      [Base64.strict_encode64(Karya::Internal::DurableQueueStore::PayloadCodec.dump(workflow_step.transform_keys(&:to_s)))]
    )
    allow(redis).to receive(:hvals).with('spec:queue_store:rows:jobs').and_return(
      [
        Base64.strict_encode64(Karya::Internal::DurableQueueStore::PayloadCodec.dump(job_row.transform_keys(&:to_s))),
        Base64.strict_encode64(Karya::Internal::DurableQueueStore::PayloadCodec.dump(other_job_row.transform_keys(&:to_s)))
      ]
    )

    rows = store.fetch_rows_for_operation(operation_name: :batch_snapshot, namespace: 'spec', request: { batch_id: :batch_one })

    expect(rows.fetch(:workflow_batches)).to eq([workflow_batch])
    expect(rows.fetch(:workflow_steps)).to eq([workflow_step])
    expect(rows.fetch(:jobs)).to eq([job_row])
  end

  it 'filters orphan reservations by worker id and applies metadata and row changes' do
    row = {
      namespace: 'spec',
      reservation_token: 'token-1',
      job_id: 'job-1',
      worker_id: 'worker-1',
      queue: 'billing',
      reserved_at: Time.utc(2026, 5, 23, 12, 0, 0),
      lease_expires_at: Time.utc(2026, 5, 23, 12, 1, 0),
      phase: :reserved
    }
    allow(redis).to receive(:hvals).and_return(
      [
        Base64.strict_encode64(
          Karya::Internal::DurableQueueStore::PayloadCodec.dump(row.transform_keys(&:to_s))
        )
      ]
    )

    rows = store.fetch_rows_for_operation(operation_name: :recover_orphaned_jobs, namespace: 'spec', request: { worker_id: 'worker-1' })
    expect(rows.fetch(:reservations)).to eq([row])

    plan = Karya::Internal::DurableQueueStore::MutationPlan.new(
      metadata_updates: { schema_version: 1, reservation_token_sequence: 2 },
      inserts: { policy_state: [{ namespace: 'spec', policy_kind: 'paused_queue', scope_kind: 'queue', scope_value: 'billing' }] },
      deletes: { reservations: [row] }
    )

    expect(store.apply_mutation_plan(plan:, namespace: 'spec')).to be_nil
    expect(redis).to have_received(:hset).at_least(:once)
    expect(redis).to have_received(:hdel).with('spec:queue_store:rows:reservations', 'spec|token-1')
  end

  it 'skips empty metadata updates' do
    plan = Karya::Internal::DurableQueueStore::MutationPlan.new(metadata_updates: {})

    expect(store.apply_mutation_plan(plan:, namespace: 'spec')).to be_nil
    expect(redis).not_to have_received(:hset).with('spec:queue_store:metadata', any_args)
  end
end
