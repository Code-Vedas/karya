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

  def rollback_batch_id(batch_id)
    internal = Karya::QueueStore::InMemory.const_get(:Internal, false)
    workflow_support = internal.const_get(:WorkflowSupport, false)
    workflow_support.const_get(:RollbackBatchId, false).new(batch_id).to_s
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
    store_state.register_batch(batch('batch-2', ['job-2']))
    store_state.register_workflow(
      batch_id: 'batch-1',
      workflow_id: 'invoice_closeout',
      step_job_ids: { 'root' => 'job-1' },
      dependency_job_ids_by_job_id: { 'job-1' => [] },
      compensation_jobs_by_step_id: {}
    )
    store_state.workflow_dependency_job_ids_by_job_id['job-1'] = []
    store_state.workflow_dependency_job_ids_by_job_id['job-2'] = []
    store_state.batches_by_id.delete('batch-1')

    store_state.prune_terminal_batches(0)

    expect(store_state.instance_variable_get(:@batch_id_by_job_id)).to eq('job-2' => 'batch-2')
    expect(store_state.workflow_registrations_by_batch_id).to eq({})
    expect(store_state.workflow_dependency_job_ids_by_job_id).to eq('job-2' => [])
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

  it 'retains terminal child batches while their parent batch is still active' do
    store_state.jobs_by_id['job-parent'] = active_job('job-parent')
    store_state.jobs_by_id['job-child'] = succeeded_job('job-child')
    store_state.register_batch(batch('parent-batch', ['job-parent']))
    store_state.register_batch(batch('child-batch', ['job-child']))
    store_state.register_workflow(
      batch_id: 'parent-batch',
      workflow_id: 'parent',
      step_job_ids: { 'child' => 'job-parent' },
      dependency_job_ids_by_job_id: {},
      compensation_jobs_by_step_id: {},
      child_workflow_ids_by_step_id: { 'child' => 'payment' }
    )
    store_state.register_workflow(
      batch_id: 'child-batch',
      workflow_id: 'payment',
      step_job_ids: { 'authorize' => 'job-child' },
      dependency_job_ids_by_job_id: {},
      compensation_jobs_by_step_id: {}
    )
    relationship = store_state.workflow_children.register(
      parent_workflow_id: 'parent',
      parent_batch_id: 'parent-batch',
      parent_step_id: 'child',
      parent_job_id: 'job-parent',
      child_workflow_id: 'payment',
      child_batch_id: 'child-batch'
    )

    expect(store_state.prune_terminal_batches(0)).to eq([])
    expect(store_state.batches_by_id.keys).to contain_exactly('parent-batch', 'child-batch')
    expect(store_state.workflow_children.for_child_batch('child-batch')).to eq(relationship)
    expect(store_state.workflow_children.expected_child_workflow_id_by_job_id).to eq('job-parent' => 'payment')
  end

  it 'does not allocate empty parent relationship indexes on read paths' do
    workflow_children = store_state.workflow_children

    expect(workflow_children.for_parent_step('missing-batch', 'missing-step')).to be_nil
    expect(workflow_children.for_parent_batch('missing-batch')).to eq([])
    expect(workflow_children.instance_variable_get(:@by_parent_batch_id)).to eq({})
  end

  it 'stores workflow registrations by batch id' do
    step_job_ids = { 'root' => 'job-root' }
    dependency_job_ids = []
    dependency_job_ids_by_job_id = { 'job-root' => dependency_job_ids }
    compensation_jobs_by_step_id = { 'root' => instance_double(Karya::Job) }

    registration = store_state.register_workflow(
      batch_id: 'batch-1',
      workflow_id: 'invoice_closeout',
      step_job_ids:,
      dependency_job_ids_by_job_id:,
      compensation_jobs_by_step_id:
    )
    step_job_ids['root'] = 'mutated'
    dependency_job_ids << 'mutated'
    dependency_job_ids_by_job_id['job-root'] = ['mutated']
    compensation_jobs_by_step_id['root'] = instance_double(Karya::Job)

    expect(registration.workflow_id).to eq('invoice_closeout')
    expect(registration.step_job_ids).to eq('root' => 'job-root')
    expect(registration.dependency_job_ids_by_job_id).to eq('job-root' => [])
    expect(registration.compensation_jobs_by_step_id.keys).to eq(['root'])
    expect(registration.step_job_ids).to be_frozen
    expect(registration.dependency_job_ids_by_job_id).to be_frozen
    expect(registration.dependency_job_ids_by_job_id.fetch('job-root')).to be_frozen
    expect(registration.compensation_jobs_by_step_id).to be_frozen
    expect(registration).to be_frozen
    expect(store_state.workflow_registrations_by_batch_id.fetch('batch-1')).to eq(registration)
    expect(store_state.workflow_registrations_by_batch_id['missing']).to be_nil
  end

  it 'cleans up child workflow relationships by parent batch' do
    workflow_children = store_state.workflow_children

    expect(workflow_children.delete_by_parent_batch('missing-batch')).to eq([])

    store_state.register_workflow(
      batch_id: 'batch-1',
      workflow_id: 'invoice_closeout',
      step_job_ids: { 'child' => 'job-child' },
      dependency_job_ids_by_job_id: {},
      compensation_jobs_by_step_id: {},
      child_workflow_ids_by_step_id: { 'child' => 'payment_flow' }
    )
    relationship = workflow_children.register(
      parent_workflow_id: 'invoice_closeout',
      parent_batch_id: 'batch-1',
      parent_step_id: 'child',
      parent_job_id: 'job-child',
      child_workflow_id: 'payment_flow',
      child_batch_id: 'child-batch-1'
    )

    expect(workflow_children.delete_by_parent_batch('batch-1')).to eq([relationship])
    expect(workflow_children.for_parent_batch('batch-1')).to eq([])
    expect(workflow_children.for_parent_job('job-child')).to be_nil
    expect(workflow_children.for_child_batch('child-batch-1')).to be_nil
    expect(workflow_children.expected_child_workflow_id_by_job_id).to eq({})
  end

  it 'cleans up child workflow relationships by child batch' do
    workflow_children = store_state.workflow_children

    expect(workflow_children.delete_by_child_batch('missing-child-batch')).to be_nil

    store_state.register_workflow(
      batch_id: 'batch-1',
      workflow_id: 'invoice_closeout',
      step_job_ids: { 'child' => 'job-child', 'sibling' => 'job-sibling' },
      dependency_job_ids_by_job_id: {},
      compensation_jobs_by_step_id: {},
      child_workflow_ids_by_step_id: { 'child' => 'payment_flow', 'sibling' => 'shipment_flow' }
    )
    relationship = workflow_children.register(
      parent_workflow_id: 'invoice_closeout',
      parent_batch_id: 'batch-1',
      parent_step_id: 'child',
      parent_job_id: 'job-child',
      child_workflow_id: 'payment_flow',
      child_batch_id: 'child-batch-1'
    )
    sibling_relationship = workflow_children.register(
      parent_workflow_id: 'invoice_closeout',
      parent_batch_id: 'batch-1',
      parent_step_id: 'sibling',
      parent_job_id: 'job-sibling',
      child_workflow_id: 'shipment_flow',
      child_batch_id: 'child-batch-2'
    )

    expect(workflow_children.delete_by_child_batch('child-batch-1')).to eq(relationship)
    expect(workflow_children.for_parent_batch('batch-1')).to eq([sibling_relationship])
    expect(workflow_children.for_parent_job('job-child')).to be_nil
    expect(workflow_children.for_child_batch('child-batch-1')).to be_nil
    expect(workflow_children.expected_child_workflow_id_by_job_id).to eq('job-sibling' => 'shipment_flow')

    expect(workflow_children.delete_by_child_batch('child-batch-2')).to eq(sibling_relationship)
    expect(workflow_children.for_parent_batch('batch-1')).to eq([])
    expect(workflow_children.for_parent_job('job-sibling')).to be_nil
    expect(workflow_children.for_child_batch('child-batch-2')).to be_nil
    expect(workflow_children.expected_child_workflow_id_by_job_id).to eq({})
  end

  it 'tolerates child workflow cleanup when the parent batch index is already gone' do
    workflow_children = store_state.workflow_children

    store_state.register_workflow(
      batch_id: 'batch-1',
      workflow_id: 'invoice_closeout',
      step_job_ids: { 'child' => 'job-child' },
      dependency_job_ids_by_job_id: {},
      compensation_jobs_by_step_id: {},
      child_workflow_ids_by_step_id: { 'child' => 'payment_flow' }
    )
    relationship = workflow_children.register(
      parent_workflow_id: 'invoice_closeout',
      parent_batch_id: 'batch-1',
      parent_step_id: 'child',
      parent_job_id: 'job-child',
      child_workflow_id: 'payment_flow',
      child_batch_id: 'child-batch-1'
    )
    workflow_children.instance_variable_get(:@by_parent_batch_id).delete('batch-1')

    expect(workflow_children.delete_by_child_batch('child-batch-1')).to eq(relationship)
    expect(workflow_children.for_parent_job('job-child')).to be_nil
    expect(workflow_children.for_child_batch('child-batch-1')).to be_nil
    expect(workflow_children.expected_child_workflow_id_by_job_id).to eq({})
  end

  it 'removes workflow metadata when pruning terminal batches' do
    store_state.jobs_by_id['job-root'] = succeeded_job('job-root')
    store_state.jobs_by_id['job-child'] = succeeded_job('job-child')
    store_state.register_batch(batch('batch-1', %w[job-root job-child]))
    store_state.workflow_dependency_job_ids_by_job_id['job-root'] = []
    store_state.workflow_dependency_job_ids_by_job_id['job-child'] = ['job-root']
    store_state.register_workflow(
      batch_id: 'batch-1',
      workflow_id: 'invoice_closeout',
      step_job_ids: { 'root' => 'job-root', 'child' => 'job-child' },
      dependency_job_ids_by_job_id: {
        'job-root' => [],
        'job-child' => ['job-root']
      },
      compensation_jobs_by_step_id: {}
    )

    expect(store_state.prune_terminal_batches(0)).to eq(['batch-1'])

    expect(store_state.workflow_registrations_by_batch_id).to eq({})
    expect(store_state.workflow_dependency_job_ids_by_job_id).to eq({})
  end

  it 'removes expected child metadata when pruning a workflow that never enqueued its child batch' do
    store_state.jobs_by_id['job-root'] = succeeded_job('job-root')
    store_state.register_batch(batch('batch-1', ['job-root']))
    store_state.register_workflow(
      batch_id: 'batch-1',
      workflow_id: 'invoice_closeout',
      step_job_ids: { 'child' => 'job-root' },
      dependency_job_ids_by_job_id: { 'job-root' => [] },
      compensation_jobs_by_step_id: {},
      child_workflow_ids_by_step_id: { 'child' => 'payment_flow' }
    )

    expect(store_state.workflow_children.expected_child_workflow_id_by_job_id).to eq('job-root' => 'payment_flow')
    expect(store_state.prune_terminal_batches(0)).to eq(['batch-1'])
    expect(store_state.workflow_children.expected_child_workflow_id_by_job_id).to eq({})
  end

  it 'removes workflow rollback metadata when pruning terminal batches' do
    store_state.jobs_by_id['job-root'] = succeeded_job('job-root')
    store_state.register_batch(batch('batch-1', ['job-root']))
    store_state.register_workflow(
      batch_id: 'batch-1',
      workflow_id: 'invoice_closeout',
      step_job_ids: { 'root' => 'job-root' },
      dependency_job_ids_by_job_id: { 'job-root' => [] },
      compensation_jobs_by_step_id: {}
    )
    store_state.register_workflow_rollback(
      batch_id: 'batch-1',
      rollback_batch_id: rollback_batch_id('batch-1'),
      reason: 'operator rollback',
      requested_at: Time.utc(2026, 4, 24, 12, 0, 0),
      compensation_job_ids: []
    )

    expect(store_state.prune_terminal_batches(0)).to eq(['batch-1'])

    expect(store_state.workflow_registrations_by_batch_id).to eq({})
    expect(store_state.workflow_rollbacks_by_batch_id).to eq({})
    expect(store_state.workflow_rollback_batch_ids).to eq({})
  end

  it 'stores workflow rollback metadata by workflow batch id' do
    compensation_job_ids = ['rollback-job-1']

    rollback = store_state.register_workflow_rollback(
      batch_id: 'batch-1',
      rollback_batch_id: rollback_batch_id('batch-1'),
      reason: 'operator rollback',
      requested_at: Time.utc(2026, 4, 24, 12, 0, 0),
      compensation_job_ids:
    )
    compensation_job_ids << 'mutated'

    expect(rollback.rollback_batch_id).to eq(rollback_batch_id('batch-1'))
    expect(rollback.compensation_job_ids).to eq(['rollback-job-1'])
    expect(rollback.compensation_job_ids).to be_frozen
    expect(rollback).to be_frozen
    expect(store_state.workflow_rollback_batch_ids).to eq(rollback_batch_id('batch-1') => true)
    expect(store_state.workflow_rollbacks_by_batch_id.fetch('batch-1')).to eq(rollback)
    expect(store_state.workflow_rollbacks_by_batch_id['missing']).to be_nil
  end
end
