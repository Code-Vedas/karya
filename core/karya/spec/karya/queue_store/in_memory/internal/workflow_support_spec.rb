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

  def rollback_job(id)
    Karya::Job.new(id:, queue: :rollback, handler: :undo, state: :submission, created_at:)
  end

  def rollback_batch_id(batch_id)
    internal = Karya::QueueStore::InMemory.const_get(:Internal, false)
    workflow_support = internal.const_get(:WorkflowSupport, false)
    workflow_support.const_get(:RollbackBatchId, false).new(batch_id).to_s
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

  it 'resolves explicit workflow step control targets in request order' do
    internal = Karya::QueueStore::InMemory.const_get(:Internal, false)
    workflow_support = internal.const_get(:WorkflowSupport, false)
    helper = workflow_support.const_get(:WorkflowControlTargets, false)
    registration = store.send(:state).register_workflow(
      batch_id: 'batch-1',
      workflow_id: 'invoice_closeout',
      step_job_ids: { 'first' => 'job-1', 'second' => 'job-2' },
      dependency_job_ids_by_job_id: {},
      compensation_jobs_by_step_id: {}
    )

    result = helper.new(registration:, step_ids: [' second ', :first]).job_ids

    expect(result).to eq(%w[job-2 job-1])
    expect(result).to be_frozen
  end

  it 'rejects invalid workflow step control target lists' do
    internal = Karya::QueueStore::InMemory.const_get(:Internal, false)
    workflow_support = internal.const_get(:WorkflowSupport, false)
    helper = workflow_support.const_get(:WorkflowControlTargets, false)
    registration = store.send(:state).register_workflow(
      batch_id: 'batch-1',
      workflow_id: 'invoice_closeout',
      step_job_ids: { 'first' => 'job-1' },
      dependency_job_ids_by_job_id: {},
      compensation_jobs_by_step_id: {}
    )

    expect { helper.new(registration:, step_ids: 'first').job_ids }
      .to raise_error(Karya::Workflow::InvalidExecutionError, 'step_ids must be an Array')
    expect { helper.new(registration:, step_ids: []).job_ids }
      .to raise_error(Karya::Workflow::InvalidExecutionError, 'step_ids must not be empty')
    expect { helper.new(registration:, step_ids: [:first, ' first ']).job_ids }
      .to raise_error(Karya::Workflow::InvalidExecutionError, 'duplicate workflow step "first"')
    expect { helper.new(registration:, step_ids: [:missing]).job_ids }
      .to raise_error(Karya::Workflow::InvalidExecutionError, 'unknown workflow step "missing"')
  end

  it 'raises workflow-domain errors for non-workflow batches' do
    expect do
      store.send(:fetch_workflow_registration, 'batch-1')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'batch "batch-1" is not a workflow batch')
  end

  it 'rewrites rollback reason validation errors into workflow terminology' do
    expect do
      store.send(:normalize_rollback_reason, " \t ")
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'reason must be present')
  end

  it 'rejects non-string rollback reasons with workflow terminology' do
    expect do
      store.send(:normalize_rollback_reason, :operator_rollback)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'reason must be a String')
  end

  it 'rejects overlong rollback reasons with workflow terminology' do
    expect do
      store.send(:normalize_rollback_reason, 'a' * 1025)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'reason must be at most 1024 characters')
  end

  it 'builds frozen rollback batch ids' do
    expect(rollback_batch_id('batch-1')).to eq('__karya_workflow_rollback_v1__62617463682d31')
    expect(rollback_batch_id('batch-1')).to be_frozen
  end

  it 'builds distinct rollback batch ids for suffixed workflow batch ids' do
    expect(rollback_batch_id('batch-1')).not_to eq(rollback_batch_id('batch-1.rollback'))
  end

  it 'builds rollback jobs in reverse definition order with serial dependencies' do
    internal = Karya::QueueStore::InMemory.const_get(:Internal, false)
    workflow_support = internal.const_get(:WorkflowSupport, false)
    helper = workflow_support.const_get(:RollbackPlan, false)
    registration = store.send(:state).register_workflow(
      batch_id: 'batch-1',
      workflow_id: 'invoice_closeout',
      step_job_ids: { 'first' => 'job-1', 'second' => 'job-2', 'third' => 'job-3' },
      dependency_job_ids_by_job_id: {},
      compensation_jobs_by_step_id: {
        'first' => rollback_job('rollback-job-1'),
        'second' => rollback_job('rollback-job-2'),
        'third' => rollback_job('rollback-job-3')
      }
    )

    result = helper.new(
      registration:,
      jobs: [job(id: 'job-1', state: :succeeded), job(id: 'job-2', state: :failed), job(id: 'job-3', state: :succeeded)]
    ).to_plan

    expect(result.jobs.map(&:id)).to eq(%w[rollback-job-3 rollback-job-1])
    expect(result.dependency_job_ids_by_job_id).to eq(
      'rollback-job-3' => [],
      'rollback-job-1' => ['rollback-job-3']
    )
    expect(result.dependency_job_ids_by_job_id.fetch('rollback-job-3')).to be_frozen
  end

  it 'builds empty rollback plans when every compensation step is skipped' do
    internal = Karya::QueueStore::InMemory.const_get(:Internal, false)
    workflow_support = internal.const_get(:WorkflowSupport, false)
    helper = workflow_support.const_get(:RollbackPlan, false)
    registration = store.send(:state).register_workflow(
      batch_id: 'batch-1',
      workflow_id: 'invoice_closeout',
      step_job_ids: { 'first' => 'job-1' },
      dependency_job_ids_by_job_id: {},
      compensation_jobs_by_step_id: { 'first' => rollback_job('rollback-job-1') }
    )

    result = helper.new(registration:, jobs: [job(id: 'job-1', state: :failed)]).to_plan

    expect(result.jobs).to eq([])
    expect(result.dependency_job_ids_by_job_id).to eq({})
  end
end
