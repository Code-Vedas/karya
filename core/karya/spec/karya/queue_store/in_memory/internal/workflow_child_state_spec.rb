# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::WorkflowChildState' do
  subject(:workflow_child_state) { described_class.new(state: store_state, now: captured_at) }

  let(:described_class) do
    Karya::QueueStore::InMemory.const_get(:Internal, false).const_get(:WorkflowChildState, false)
  end
  let(:store_state) do
    Karya::QueueStore::InMemory.const_get(:Internal, false).const_get(:StoreState, false).new(expired_tombstone_limit: 16)
  end
  let(:captured_at) { Time.utc(2026, 4, 25, 12, 0, 0) }

  def batch(id, job_ids)
    Karya::Workflow::Batch.new(id:, job_ids:, created_at: captured_at)
  end

  def job(id, state:)
    Karya::Job.new(id:, queue: 'billing', handler: 'billing_sync', state:, created_at: captured_at)
  end

  it 'includes nested child workflow relationship snapshots when deriving child state' do
    fresh_workflow_child_state = described_class.new(state: store_state, now: captured_at)

    store_state.jobs_by_id['job-authorize'] = job('job-authorize', state: :succeeded)
    store_state.jobs_by_id['job-risk_review'] = job('job-risk_review', state: :queued)
    store_state.jobs_by_id['job-approve'] = job('job-approve', state: :succeeded)
    store_state.register_batch(batch('payment-batch', %w[job-authorize job-risk_review]))
    store_state.register_batch(batch('risk-review-batch', ['job-approve']))
    store_state.register_workflow(
      batch_id: 'payment-batch',
      workflow_id: 'payment',
      step_job_ids: {
        'authorize' => 'job-authorize',
        'risk_review' => 'job-risk_review'
      },
      dependency_job_ids_by_job_id: {
        'job-authorize' => [],
        'job-risk_review' => ['job-authorize']
      },
      compensation_jobs_by_step_id: {},
      child_workflow_ids_by_step_id: { 'risk_review' => 'risk_review' }
    )
    store_state.register_workflow(
      batch_id: 'risk-review-batch',
      workflow_id: 'risk_review',
      step_job_ids: { 'approve' => 'job-approve' },
      dependency_job_ids_by_job_id: { 'job-approve' => [] },
      compensation_jobs_by_step_id: {}
    )
    store_state.workflow_children.register(
      parent_workflow_id: 'parent',
      parent_batch_id: 'parent-batch',
      parent_step_id: 'payment_subflow',
      parent_job_id: 'job-parent',
      child_workflow_id: 'payment',
      child_batch_id: 'payment-batch'
    )
    store_state.workflow_children.register(
      parent_workflow_id: 'payment',
      parent_batch_id: 'payment-batch',
      parent_step_id: 'risk_review',
      parent_job_id: 'job-risk_review',
      child_workflow_id: 'risk_review',
      child_batch_id: 'risk-review-batch'
    )

    expect(fresh_workflow_child_state.resolve('payment-batch')).to eq(:running)
    expect(workflow_child_state.resolve('risk-review-batch')).to eq(:succeeded)
    expect(workflow_child_state.resolve('payment-batch')).to eq(:running)
  end

  it 'raises a workflow execution error for child workflow cycles' do
    store_state.jobs_by_id['job-a'] = job('job-a', state: :queued)
    store_state.jobs_by_id['job-b'] = job('job-b', state: :queued)
    store_state.register_batch(batch('batch-a', ['job-a']))
    store_state.register_batch(batch('batch-b', ['job-b']))
    store_state.register_workflow(
      batch_id: 'batch-a',
      workflow_id: 'workflow-a',
      step_job_ids: { 'step_a' => 'job-a' },
      dependency_job_ids_by_job_id: { 'job-a' => [] },
      compensation_jobs_by_step_id: {},
      child_workflow_ids_by_step_id: { 'step_a' => 'workflow-b' }
    )
    store_state.register_workflow(
      batch_id: 'batch-b',
      workflow_id: 'workflow-b',
      step_job_ids: { 'step_b' => 'job-b' },
      dependency_job_ids_by_job_id: { 'job-b' => [] },
      compensation_jobs_by_step_id: {},
      child_workflow_ids_by_step_id: { 'step_b' => 'workflow-a' }
    )
    store_state.workflow_children.register(
      parent_workflow_id: 'workflow-a',
      parent_batch_id: 'batch-a',
      parent_step_id: 'step_a',
      parent_job_id: 'job-a',
      child_workflow_id: 'workflow-b',
      child_batch_id: 'batch-b'
    )
    store_state.workflow_children.register(
      parent_workflow_id: 'workflow-b',
      parent_batch_id: 'batch-b',
      parent_step_id: 'step_b',
      parent_job_id: 'job-b',
      child_workflow_id: 'workflow-a',
      child_batch_id: 'batch-a'
    )

    expect { workflow_child_state.resolve('batch-a') }.to raise_error(
      Karya::Workflow::InvalidExecutionError,
      'child workflow cycle detected at batch "batch-a"'
    )
  end
end
