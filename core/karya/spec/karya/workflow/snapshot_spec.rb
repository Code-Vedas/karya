# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Workflow::Snapshot do
  let(:captured_at) { Time.utc(2026, 4, 24, 12, 0, 0) }

  around do |example|
    Karya::JobLifecycle.send(:clear_extensions!)
    example.run
    Karya::JobLifecycle.send(:clear_extensions!)
  end

  def job(id:, state:)
    Karya::Job.new(id:, queue: :billing, handler: :sync_billing, state:, created_at: captured_at)
  end

  def rollback
    Karya::Workflow::RollbackSnapshot.new(
      workflow_batch_id: 'batch_1',
      rollback_batch_id: :'batch_1.rollback',
      reason: 'operator rollback',
      requested_at: captured_at + 1,
      compensation_job_ids: ['rollback-job-root']
    )
  end

  def snapshot(jobs:, step_job_ids: nil, dependencies: {}, rollback: nil)
    described_class.new(
      workflow_id: ' invoice_closeout ',
      batch_id: ' batch_1 ',
      captured_at:,
      step_job_ids: step_job_ids || jobs.to_h { |workflow_job| [workflow_job.id.delete_prefix('job_'), workflow_job.id] },
      dependency_job_ids_by_job_id: dependencies,
      jobs:,
      rollback:
    )
  end

  it 'builds an immutable workflow snapshot' do
    jobs = [job(id: 'job_root', state: :succeeded), job(id: 'job_child', state: :queued)]

    result = snapshot(jobs:, step_job_ids: { root: 'job_root', child: 'job_child' }, dependencies: { 'job_child' => ['job_root'] })

    expect(result).to have_attributes(
      workflow_id: 'invoice_closeout',
      batch_id: 'batch_1',
      captured_at:,
      job_ids: %w[job_root job_child],
      step_states: { 'root' => :succeeded, 'child' => :queued },
      state_counts: { succeeded: 1, queued: 1 },
      total_count: 2,
      completed_count: 1,
      failed_count: 0,
      state: :running
    )
    expect(result.steps.map(&:step_id)).to eq(%w[root child])
    expect(result.step(:child)).to have_attributes(
      step_id: 'child',
      job_id: 'job_child',
      state: :queued,
      prerequisite_job_ids: ['job_root'],
      prerequisite_states: { 'job_root' => :succeeded }
    )
    expect(result.fetch_step(' root ').job).to eq(jobs.fetch(0))
    expect(result.job_for_step(:child)).to eq(jobs.fetch(1))
    expect(result.job_id_for_step(:child)).to eq('job_child')
    expect(result.state_for_step(:child)).to eq(:queued)
    expect(result.rollback_requested?).to be(false)
    expect(result.rollback).to be_nil
    expect(result).to be_frozen
    expect(result.jobs).to be_frozen
    expect(result.step_states).to be_frozen
    expect(result.state_counts).to be_frozen
  end

  it 'exposes rollback metadata when requested' do
    result = snapshot(jobs: [job(id: 'job_root', state: :failed)], rollback:)

    expect(result.rollback_requested?).to be(true)
    expect(result.rollback).to have_attributes(
      workflow_batch_id: 'batch_1',
      rollback_batch_id: 'batch_1.rollback',
      reason: 'operator rollback',
      compensation_job_ids: ['rollback-job-root']
    )
  end

  it 'raises execution errors for unknown runtime step lookup' do
    result = snapshot(jobs: [job(id: 'job_root', state: :queued)])

    expect(result.step(:missing)).to be_nil
    expect do
      result.fetch_step(:missing)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'unknown workflow step "missing"')
  end

  it 'rejects invalid identifiers and timestamps' do
    jobs = [job(id: 'job_root', state: :queued)]

    expect do
      described_class.new(
        workflow_id: nil,
        batch_id: :batch,
        captured_at:,
        step_job_ids: { root: 'job_root' },
        dependency_job_ids_by_job_id: {},
        jobs:
      )
    end.to raise_error(Karya::Workflow::InvalidDefinitionError, 'workflow_id must be present')

    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: nil,
        captured_at:,
        step_job_ids: { root: 'job_root' },
        dependency_job_ids_by_job_id: {},
        jobs:
      )
    end.to raise_error(Karya::Workflow::InvalidBatchError, 'batch_id must be present')

    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: :batch,
        captured_at: 'now',
        step_job_ids: { root: 'job_root' },
        dependency_job_ids_by_job_id: {},
        jobs:
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'captured_at must be a Time')
  end

  it 'validates step mappings and job lists' do
    jobs = [job(id: 'job_root', state: :queued)]

    expect do
      snapshot(jobs:, step_job_ids: 'root')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'step_job_ids must be a Hash')

    expect do
      snapshot(jobs:, step_job_ids: {})
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'workflow snapshot must include at least one step')

    expect do
      snapshot(jobs:, step_job_ids: { root: 'job_root', ' root ' => 'job_root' })
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'duplicate workflow step "root"')

    expect do
      snapshot(jobs:, step_job_ids: { root: nil })
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'job_id must be present')

    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: :batch,
        captured_at:,
        step_job_ids: { root: 'job_root' },
        dependency_job_ids_by_job_id: {},
        jobs: 'job_root'
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'jobs must be an Array')

    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: :batch,
        captured_at:,
        step_job_ids: { root: 'job_root' },
        dependency_job_ids_by_job_id: {},
        jobs: []
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'workflow snapshot must include at least one job')

    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: :batch,
        captured_at:,
        step_job_ids: { root: 'job_root' },
        dependency_job_ids_by_job_id: {},
        jobs: ['job_root']
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'jobs entries must be Karya::Job')

    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: :batch,
        captured_at:,
        step_job_ids: { root: 'job_root' },
        dependency_job_ids_by_job_id: {},
        jobs:,
        unexpected: true
      )
    end.to raise_error(ArgumentError, 'unknown keyword: :unexpected')
  end

  it 'validates rollback metadata input' do
    jobs = [job(id: 'job_root', state: :queued)]

    expect do
      described_class.new(
        workflow_id: :workflow,
        batch_id: :batch,
        captured_at:,
        step_job_ids: { root: 'job_root' },
        dependency_job_ids_by_job_id: {},
        jobs:,
        rollback: 'rollback'
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'rollback must be Karya::Workflow::RollbackSnapshot')
  end

  it 'validates dependency mappings and membership' do
    jobs = [job(id: 'job_root', state: :queued)]

    expect do
      snapshot(jobs:, dependencies: 'job_root')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'dependency_job_ids_by_job_id must be a Hash')

    expect do
      snapshot(jobs:, dependencies: { 'job_root' => 'missing' })
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'dependency job ids must be an Array')

    expect do
      snapshot(jobs:, dependencies: { 'job_root' => [], ' job_root ' => [] })
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'duplicate dependency job id "job_root"')

    expect do
      snapshot(jobs:, step_job_ids: { root: 'job_other' })
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'step_job_ids must match jobs in order')
  end

  it 'derives workflow states' do
    expect(snapshot(jobs: [job(id: 'job_root', state: :queued)]).state).to eq(:pending)
    expect(snapshot(jobs: [job(id: 'job_root', state: :reserved)]).state).to eq(:running)
    expect(snapshot(jobs: [job(id: 'job_root', state: :running)]).state).to eq(:running)
    expect(snapshot(jobs: [job(id: 'job_root', state: :retry_pending)]).state).to eq(:running)
    expect(snapshot(jobs: [job(id: 'job_root', state: :succeeded)]).state).to eq(:succeeded)
    expect(snapshot(jobs: [job(id: 'job_root', state: :cancelled)]).state).to eq(:cancelled)
    expect(snapshot(jobs: [job(id: 'job_root', state: :failed)]).state).to eq(:failed)
    expect(snapshot(jobs: [job(id: 'job_root', state: :dead_letter)]).state).to eq(:failed)
  end

  it 'treats completed progress with ready queued work as running' do
    result = snapshot(
      jobs: [job(id: 'job_root', state: :succeeded), job(id: 'job_child', state: :queued)],
      step_job_ids: { root: 'job_root', child: 'job_child' },
      dependencies: { 'job_child' => ['job_root'] }
    )

    expect(result.state).to eq(:running)
  end

  it 'derives blocked and terminal mixed workflow states' do
    root = job(id: 'job_root', state: :queued)
    child = job(id: 'job_child', state: :queued)

    blocked = snapshot(
      jobs: [root, child],
      step_job_ids: { root: 'job_root', child: 'job_child' },
      dependencies: { 'job_child' => ['job_root'] }
    )
    expect(blocked.state).to eq(:blocked)

    missing_dependency = snapshot(
      jobs: [child],
      step_job_ids: { child: 'job_child' },
      dependencies: { 'job_child' => ['missing'] }
    )
    expect(missing_dependency.state).to eq(:blocked)

    terminal_mixed = snapshot(
      jobs: [job(id: 'job_root', state: :succeeded), job(id: 'job_child', state: :cancelled)],
      step_job_ids: { root: 'job_root', child: 'job_child' }
    )
    expect(terminal_mixed.state).to eq(:failed)
  end

  it 'treats custom nonterminal lifecycle states as running' do
    Karya::JobLifecycle.register_state(:awaiting_review)

    expect(snapshot(jobs: [job(id: 'job_root', state: :awaiting_review)]).state).to eq(:running)
  end
end
