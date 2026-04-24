# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::StoreState' do
  subject(:store_state) { described_class.new(expired_tombstone_limit: 16) }

  let(:described_class) do
    Karya::QueueStore::InMemory.const_get(:Internal, false).const_get(:StoreState, false)
  end
  let(:created_at) { Time.utc(2026, 4, 1, 12, 0, 0) }

  def batch(id, job_ids)
    Karya::Workflow::Batch.new(id:, job_ids:, created_at:)
  end

  def succeeded_job(id)
    Karya::Job.new(id:, queue: 'billing', handler: 'billing_sync', state: :succeeded, created_at:)
  end

  def active_job(id)
    Karya::Job.new(id:, queue: 'billing', handler: 'billing_sync', state: :queued, created_at:)
  end

  it 'ignores execution tokens that are not present' do
    store_state.execution_tokens_in_order << 'lease-1'

    store_state.delete_execution_token('missing-token')

    expect(store_state.execution_tokens_in_order).to eq(['lease-1'])
  end

  it 'does nothing when deleting a reservation token that is not in the ordering array' do
    expect(store_state.delete_reservation_token('missing-token')).to be_nil
  end

  it 'does not duplicate expired reservation tombstones' do
    store_state.mark_expired('expired-token')

    expect do
      store_state.mark_expired('expired-token')
    end.not_to(change(store_state, :expired_reservation_tokens_in_order))
  end

  it 'does not duplicate retry-pending job ids' do
    expect(store_state.register_retry_pending('job-1')).to eq(['job-1'])

    expect do
      store_state.register_retry_pending('job-1')
    end.not_to(change(store_state, :retry_pending_job_ids))

    expect(store_state.register_retry_pending('job-1')).to eq(['job-1'])
  end

  it 'keeps batches with missing member jobs during terminal batch pruning' do
    store_state.register_batch(batch('batch-1', ['missing-job']))

    store_state.prune_terminal_batches(0)

    expect(store_state.batches_by_id.keys).to eq(['batch-1'])
  end

  it 'does not prune terminal batches for changed jobs without batch membership' do
    unrelated_job = succeeded_job('unrelated-job')

    expect(store_state.prune_terminal_batches(0, changed_job: unrelated_job)).to eq([])
  end

  it 'records already-terminal batches when registering batch state' do
    store_state.jobs_by_id['job-1'] = succeeded_job('job-1')

    store_state.register_batch(batch('batch-1', ['job-1']))

    expect(store_state.prune_terminal_batches(0)).to eq(['batch-1'])
  end

  it 'skips stale terminal batch ids during pruning' do
    store_state.jobs_by_id['job-1'] = succeeded_job('job-1')
    store_state.register_batch(batch('batch-1', ['job-1']))
    store_state.batches_by_id.delete('batch-1')

    expect(store_state.prune_terminal_batches(0)).to eq([])
  end

  it 'removes stale job batch membership when pruning a missing batch entry' do
    store_state.jobs_by_id['job-1'] = succeeded_job('job-1')
    store_state.register_batch(batch('batch-1', ['job-1']))
    store_state.batches_by_id.delete('batch-1')

    store_state.prune_terminal_batches(0)

    expect(store_state.instance_variable_get(:@batch_id_by_job_id)).to eq({})
  end

  it 'leaves stale changed-job batch membership for explicit pruning cleanup' do
    terminal_job = succeeded_job('job-1')
    store_state.jobs_by_id['job-1'] = terminal_job
    store_state.register_batch(batch('batch-1', ['job-1']))
    store_state.batches_by_id.delete('batch-1')

    expect(store_state.prune_terminal_batches(10, changed_job: terminal_job)).to eq([])
    expect(store_state.instance_variable_get(:@batch_id_by_job_id)).to eq('job-1' => 'batch-1')
  end

  it 'prunes terminal batches in terminal completion order' do
    store_state.register_batch(batch('batch-1', ['job-1']))
    store_state.register_batch(batch('batch-2', ['job-2']))

    store_state.jobs_by_id['job-2'] = succeeded_job('job-2')
    store_state.prune_terminal_batches(10, changed_job: succeeded_job('job-2'))
    store_state.jobs_by_id['job-1'] = succeeded_job('job-1')
    store_state.prune_terminal_batches(10, changed_job: succeeded_job('job-1'))

    expect(store_state.prune_terminal_batches(1)).to eq(['batch-2'])
    expect(store_state.batches_by_id.keys).to eq(['batch-1'])
  end

  it 'removes terminal ordering when a member job becomes non-terminal again' do
    store_state.register_batch(batch('batch-1', ['job-1']))
    terminal_job = succeeded_job('job-1')
    queued_job = active_job('job-1')

    store_state.jobs_by_id['job-1'] = terminal_job
    store_state.prune_terminal_batches(10, changed_job: terminal_job)
    store_state.jobs_by_id['job-1'] = queued_job
    store_state.prune_terminal_batches(10, changed_job: queued_job)

    store_state.prune_terminal_batches(0)

    expect(store_state.batches_by_id.keys).to eq(['batch-1'])
  end

  it 'stores workflow registrations by batch id' do
    registration = store_state.register_workflow(
      batch_id: 'batch-1',
      workflow_id: 'invoice_closeout',
      step_job_ids: { 'root' => 'job-root' }
    )

    expect(registration.workflow_id).to eq('invoice_closeout')
    expect(registration.step_job_ids).to eq('root' => 'job-root')
    expect(registration).to be_frozen
    expect(store_state.workflow_registrations_by_batch_id['batch-1']).to eq(registration)
    expect(store_state.workflow_registrations_by_batch_id['missing']).to be_nil
  end
end
