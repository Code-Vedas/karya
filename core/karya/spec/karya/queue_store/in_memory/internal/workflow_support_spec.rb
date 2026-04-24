# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::WorkflowSupport' do
  subject(:store) { Karya::QueueStore::InMemory.new }

  let(:created_at) { Time.utc(2026, 4, 24, 12, 0, 0) }

  def job(id:, state:)
    Karya::Job.new(id:, queue: :billing, handler: :sync_billing, state:, created_at:)
  end

  it 'treats non-workflow jobs and root workflow jobs as ready' do
    plain_job = job(id: 'job-1', state: :queued)
    root_job = job(id: 'job-2', state: :queued)
    store.send(:state).workflow_dependency_job_ids_by_job_id['job-2'] = []

    expect(store.send(:workflow_dependencies_satisfied?, plain_job)).to be(true)
    expect(store.send(:workflow_dependencies_satisfied?, root_job)).to be(true)
  end

  it 'requires every prerequisite job to be succeeded' do
    dependent = job(id: 'job-3', state: :queued)
    succeeded = job(id: 'job-1', state: :succeeded)
    queued = job(id: 'job-2', state: :queued)
    store.send(:state).jobs_by_id['job-1'] = succeeded
    store.send(:state).jobs_by_id['job-2'] = queued
    store.send(:state).workflow_dependency_job_ids_by_job_id['job-3'] = %w[job-1 job-2]

    expect(store.send(:workflow_dependencies_satisfied?, dependent)).to be(false)

    store.send(:state).jobs_by_id['job-2'] = job(id: 'job-2', state: :reserved)
    expect(store.send(:workflow_dependencies_satisfied?, dependent)).to be(false)

    store.send(:state).jobs_by_id['job-2'] = job(id: 'job-2', state: :succeeded)
    expect(store.send(:workflow_dependencies_satisfied?, dependent)).to be(true)
  end

  it 'treats missing prerequisite jobs as blocked' do
    dependent = job(id: 'job-2', state: :queued)
    store.send(:state).workflow_dependency_job_ids_by_job_id['job-2'] = ['missing']

    expect(store.send(:workflow_dependencies_satisfied?, dependent)).to be(false)
  end

  it 'builds step-to-job metadata in workflow definition order' do
    internal = Karya::QueueStore::InMemory.const_get(:Internal, false)
    workflow_support = internal.const_get(:WorkflowSupport, false)
    helper = workflow_support.const_get(:StepJobIds, false)
    definition = Karya::Workflow.define(:ordered) do
      step :first, handler: :sync_billing
      step :second, handler: :sync_billing
    end

    result = helper.new(
      definition:,
      jobs: [job(id: 'job-1', state: :submission), job(id: 'job-2', state: :submission)]
    ).to_h

    expect(result).to eq('first' => 'job-1', 'second' => 'job-2')
    expect(result).to be_frozen
  end

  it 'raises workflow-domain errors for non-workflow batches' do
    expect do
      store.send(:fetch_workflow_registration, 'batch-1')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'batch "batch-1" is not a workflow batch')
  end
end
