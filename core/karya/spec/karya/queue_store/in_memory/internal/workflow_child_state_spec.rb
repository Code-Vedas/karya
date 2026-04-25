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
end
