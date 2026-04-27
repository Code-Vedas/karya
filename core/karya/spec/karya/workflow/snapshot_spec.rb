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

  def child_workflow(state: :running)
    Karya::Workflow::ChildWorkflowSnapshot.new(
      parent_workflow_id: :invoice_closeout,
      parent_batch_id: 'batch_1',
      parent_step_id: :child,
      parent_job_id: :job_child,
      child_workflow_id: :payment,
      child_batch_id: :payment_batch,
      child_state: state
    )
  end

  def interaction(kind: :signal, name: :manager_approved, payload: {}, received_at: captured_at + 2)
    Karya::Workflow::InteractionSnapshot.new(kind:, name:, payload:, received_at:)
  end

  def snapshot(jobs:, **options)
    described_class.new(
      workflow_id: ' invoice_closeout ',
      batch_id: ' batch_1 ',
      captured_at:,
      step_job_ids: options.fetch(:step_job_ids, jobs.to_h { |workflow_job| [workflow_job.id.delete_prefix('job_'), workflow_job.id] }),
      dependency_job_ids_by_job_id: options.fetch(:dependencies, {}),
      jobs:,
      child_workflow_ids_by_step_id: options.fetch(:child_workflow_ids_by_step_id, {}),
      approval_requirements_by_job_id: options.fetch(:approval_requirements_by_job_id, {}),
      approval_decisions_by_job_id: options.fetch(:approval_decisions_by_job_id, {}),
      child_workflows: options.fetch(:child_workflows, []),
      interactions: options.fetch(:interactions, []),
      interaction_requirements_by_job_id: options.fetch(:interaction_requirements_by_job_id, {}),
      interaction_received_at_by_job_id: options.fetch(:interaction_received_at_by_job_id, {}),
      parent: options.fetch(:parent, nil),
      pause_requested_at: options.fetch(:pause_requested_at, nil),
      rollback: options.fetch(:rollback, nil)
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
    expect(result.interactions).to eq([])
    expect(result.signals).to eq([])
    expect(result.events).to eq([])
    expect(result).to be_frozen
    expect(result.jobs).to be_frozen
    expect(result.step_states).to be_frozen
    expect(result.state_counts).to be_frozen
  end

  it 'exposes workflow interaction snapshots and filtered readers' do
    signal = interaction(kind: :signal, name: :manager_approved, payload: { 'approved_by' => 'ops' })
    event = interaction(kind: :event, name: :payment_received, payload: { 'source' => 'stripe' })

    result = snapshot(jobs: [job(id: 'job_root', state: :queued)], interactions: [signal, event])

    expect(result.interactions).to eq([signal, event])
    expect(result.signals).to eq([signal])
    expect(result.events).to eq([event])
  end

  it 'blocks waiting interaction-gated steps until the matching interaction is delivered' do
    jobs = [job(id: 'job_capture', state: :queued)]
    blocked = snapshot(
      jobs:,
      step_job_ids: { capture_payment: 'job_capture' },
      interaction_requirements_by_job_id: { 'job_capture' => { kind: :event, name: :payment_received } }
    )
    ready = snapshot(
      jobs:,
      step_job_ids: { capture_payment: 'job_capture' },
      interaction_requirements_by_job_id: { 'job_capture' => { kind: :event, name: :payment_received } },
      interactions: [interaction(kind: :event, name: :payment_received)]
    )

    expect(blocked.fetch_step(:capture_payment)).to be_blocked
    expect(blocked.state).to eq(:blocked)
    expect(ready.fetch_step(:capture_payment)).to be_ready
    expect(ready.state).to eq(:pending)
  end

  it 'reports approval-frontier workflows as awaiting_approval and exposes checkpoint state' do
    jobs = [job(id: 'job_approve', state: :queued)]
    awaiting = snapshot(
      jobs:,
      step_job_ids: { approve: 'job_approve' },
      approval_requirements_by_job_id: { 'job_approve' => { name: :manager_approved } }
    )
    approved = snapshot(
      jobs:,
      step_job_ids: { approve: 'job_approve' },
      approval_requirements_by_job_id: { 'job_approve' => { name: :manager_approved } },
      approval_decisions_by_job_id: { 'job_approve' => { state: :approved, decided_at: captured_at + 3 } }
    )

    expect(awaiting.fetch_step(:approve)).to be_awaiting_approval
    expect(awaiting.state).to eq(:awaiting_approval)
    expect(approved.fetch_step(:approve)).to be_ready
    expect(approved.fetch_step(:approve)).to have_attributes(
      approval_name: 'manager_approved',
      approval_state: :approved,
      approval_decided_at: captured_at + 3,
      approval_received_at: captured_at + 3
    )
    expect(approved.state).to eq(:pending)
  end

  it 'keeps signal-delivered approvals visible when other checkpoints were explicitly approved' do
    jobs = [
      job(id: 'job_manager', state: :queued),
      job(id: 'job_finance', state: :queued)
    ]
    result = snapshot(
      jobs:,
      step_job_ids: {
        manager: 'job_manager',
        finance: 'job_finance'
      },
      approval_requirements_by_job_id: {
        'job_manager' => { name: :manager_approved },
        'job_finance' => { name: :finance_approved }
      },
      approval_decisions_by_job_id: {
        'job_manager' => { state: :approved, decided_at: captured_at + 1 }
      },
      interactions: [interaction(kind: :signal, name: :finance_approved, received_at: captured_at + 2)]
    )

    expect(result.fetch_step(:manager)).to be_ready
    expect(result.fetch_step(:finance)).to be_ready
    expect(result.fetch_step(:finance).approval_received_at).to eq(captured_at + 2)
  end

  it 'reports drained paused workflows as paused without changing the frontier step set' do
    jobs = [job(id: 'job_approve', state: :queued)]
    paused = snapshot(
      jobs:,
      step_job_ids: { approve: 'job_approve' },
      approval_requirements_by_job_id: { 'job_approve' => { name: :manager_approved } },
      pause_requested_at: captured_at + 4
    )

    expect(paused.pause_requested_at).to eq(captured_at + 4)
    expect(paused.fetch_step(:approve)).to be_awaiting_approval
    expect(paused.state).to eq(:paused)
  end

  it 'accepts explicit interaction delivery timestamps for step readiness separate from inspection history' do
    jobs = [job(id: 'job_capture', state: :queued)]
    result = snapshot(
      jobs:,
      step_job_ids: { capture_payment: 'job_capture' },
      interaction_requirements_by_job_id: { 'job_capture' => { kind: :event, name: :payment_received } },
      interaction_received_at_by_job_id: { 'job_capture' => captured_at + 3 },
      interactions: []
    )

    expect(result.fetch_step(:capture_payment)).to be_ready
    expect(result.interactions).to eq([])
  end

  it 'marks every step that shares one interaction requirement as ready once delivered' do
    jobs = [job(id: 'job_capture', state: :queued), job(id: 'job_notify', state: :queued)]
    result = snapshot(
      jobs:,
      step_job_ids: { capture_payment: 'job_capture', notify_customer: 'job_notify' },
      interaction_requirements_by_job_id: {
        'job_capture' => { kind: :event, name: :payment_received },
        'job_notify' => { kind: :event, name: :payment_received }
      },
      interactions: [interaction(kind: :event, name: :payment_received)]
    )

    expect(result.fetch_step(:capture_payment)).to be_ready
    expect(result.fetch_step(:notify_customer)).to be_ready
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

  it 'exposes parent and child workflow relationship metadata' do
    jobs = [job(id: 'job_root', state: :succeeded), job(id: 'job_child', state: :queued)]
    relationship = child_workflow(state: :succeeded)

    result = snapshot(
      jobs:,
      step_job_ids: { root: 'job_root', child: 'job_child' },
      dependencies: { 'job_child' => ['job_root'] },
      child_workflow_ids_by_step_id: { child: :payment },
      child_workflows: [relationship]
    )

    expect(result.child_workflows).to eq([relationship])
    expect(result.child_workflow(:child)).to eq(relationship)
    expect(result.fetch_child_workflow(' child ')).to eq(relationship)
    expect(result.parent).to be_nil
    expect(result.fetch_step(:child)).to have_attributes(
      child_workflow_id: 'payment',
      child_workflow: relationship
    )
    expect(result.fetch_step(:child)).to be_ready
  end

  it 'treats waiting child workflow steps as blocked until the child succeeds' do
    jobs = [job(id: 'job_child', state: :queued)]

    missing_child = snapshot(
      jobs:,
      step_job_ids: { child: 'job_child' },
      child_workflow_ids_by_step_id: { child: :payment }
    )
    running_child = snapshot(
      jobs:,
      step_job_ids: { child: 'job_child' },
      child_workflow_ids_by_step_id: { child: :payment },
      child_workflows: [child_workflow(state: :running)]
    )
    succeeded_child = snapshot(
      jobs:,
      step_job_ids: { child: 'job_child' },
      child_workflow_ids_by_step_id: { child: :payment },
      child_workflows: [child_workflow(state: :succeeded)]
    )

    expect(missing_child.state).to eq(:blocked)
    expect(running_child.state).to eq(:blocked)
    expect(succeeded_child.state).to eq(:pending)
  end

  it 'exposes parent workflow metadata for child batch snapshots' do
    jobs = [job(id: 'job_authorize', state: :queued)]
    relationship = Karya::Workflow::ChildWorkflowSnapshot.new(
      parent_workflow_id: :invoice_closeout,
      parent_batch_id: 'parent_batch',
      parent_step_id: :child,
      parent_job_id: :job_child,
      child_workflow_id: :payment,
      child_batch_id: 'batch_1',
      child_state: :running
    )

    result = described_class.new(
      workflow_id: 'payment',
      batch_id: 'batch_1',
      captured_at:,
      step_job_ids: { authorize: 'job_authorize' },
      dependency_job_ids_by_job_id: {},
      jobs:,
      parent: relationship
    )

    expect(result.parent).to eq(relationship)
  end

  it 'validates parent and child workflow relationship metadata' do
    jobs = [job(id: 'job_child', state: :queued)]
    relationship = child_workflow(state: :running)

    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, parent: 'parent')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'parent must be Karya::Workflow::ChildWorkflowSnapshot')
    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, child_workflow_ids_by_step_id: 'child')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'child_workflow_ids_by_step_id must be a Hash')
    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, child_workflows: 'child')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'child_workflows must be an Array')
    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, interactions: 'signal')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'interactions must be an Array')
    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, interactions: ['signal'])
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'interactions entries must be Karya::Workflow::InteractionSnapshot')
    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, interaction_received_at_by_job_id: 'signal')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'interaction_received_at_by_job_id must be a Hash')
    expect do
      snapshot(
        jobs:,
        step_job_ids: { child: 'job_child' },
        interaction_received_at_by_job_id: {
          ' job_child ' => captured_at + 1,
          job_child: captured_at + 2
        }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'duplicate interaction delivery job "job_child"')
    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, child_workflows: ['child'])
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'child_workflows entries must be Karya::Workflow::ChildWorkflowSnapshot')
    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, child_workflows: [relationship])
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'unknown child workflow step "child"')

    mismatched_relationship = child_workflow(state: :running)
    expect do
      snapshot(
        jobs:,
        step_job_ids: { child: 'job_child' },
        child_workflow_ids_by_step_id: { child: :shipment },
        child_workflows: [mismatched_relationship]
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'child workflow relationship id must match declared child workflow id')
    expect do
      snapshot(
        jobs:,
        step_job_ids: { child: 'job_child' },
        child_workflow_ids_by_step_id: { child: :payment },
        child_workflows: [relationship, relationship]
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'duplicate child workflow for step "child"')
  end

  it 'raises execution errors for unknown runtime step lookup' do
    result = snapshot(jobs: [job(id: 'job_root', state: :queued)])

    expect(result.step(:missing)).to be_nil
    expect do
      result.fetch_step(:missing)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'unknown workflow step "missing"')
    expect(result.child_workflow(:missing)).to be_nil
    expect do
      result.fetch_child_workflow(:missing)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'unknown child workflow for step "missing"')
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

  it 'validates interaction requirement metadata' do
    jobs = [job(id: 'job_child', state: :queued)]

    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, interaction_requirements_by_job_id: 'signal')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'interaction_requirements_by_job_id must be a Hash')

    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, interaction_requirements_by_job_id: { 'job_child' => 'signal' })
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'interaction requirement must be a Hash')

    expect do
      snapshot(
        jobs:,
        step_job_ids: { child: 'job_child' },
        interaction_requirements_by_job_id: { 'job_child' => { kind: :webhook, name: :payment_received } }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'interaction requirement kind must be :signal or :event')

    expect do
      snapshot(
        jobs:,
        step_job_ids: { child: 'job_child' },
        interaction_requirements_by_job_id: { 'job_child' => { kind: 123, name: :payment_received } }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'interaction requirement kind must be :signal or :event')

    expect do
      snapshot(
        jobs:,
        step_job_ids: { child: 'job_child' },
        interaction_requirements_by_job_id: { 'job_child' => { kind: :signal, name: '   ' } }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'interaction_name must be present')

    expect do
      snapshot(
        jobs:,
        step_job_ids: { child: 'job_child' },
        interaction_requirements_by_job_id: {
          ' job_child ' => { kind: :signal, name: :manager_approved },
          job_child: { kind: :signal, name: :manager_approved }
        }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'duplicate interaction requirement job "job_child"')
  end

  it 'validates approval requirement metadata' do
    jobs = [job(id: 'job_child', state: :queued)]

    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, approval_requirements_by_job_id: 'approval')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'approval_requirements_by_job_id must be a Hash')

    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, approval_requirements_by_job_id: { 'job_child' => 'approval' })
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'approval requirement must be a Hash')

    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, approval_requirements_by_job_id: { 'job_child' => {} })
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'approval requirement must include :name')

    expect do
      snapshot(
        jobs:,
        step_job_ids: { child: 'job_child' },
        approval_requirements_by_job_id: { ' job_child ' => { name: :manager_approved }, job_child: { name: :manager_approved } }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'duplicate approval requirement job "job_child"')
  end

  it 'validates approval decision metadata' do
    jobs = [job(id: 'job_child', state: :queued)]

    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, approval_decisions_by_job_id: { 'job_child' => [] })
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'approval decision must be a Hash')

    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, approval_decisions_by_job_id: 'approved')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'approval_decisions_by_job_id must be a Hash')

    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, approval_decisions_by_job_id: { 'job_child' => { decided_at: captured_at } })
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'approval decision must include :state')

    expect do
      snapshot(jobs:, step_job_ids: { child: 'job_child' }, approval_decisions_by_job_id: { 'job_child' => { state: :approved } })
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'approval decision must include :decided_at')

    expect do
      snapshot(
        jobs:,
        step_job_ids: { child: 'job_child' },
        approval_decisions_by_job_id: { 'job_child' => { state: :later, decided_at: captured_at } }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'approval decision state must be :approved or :rejected')

    expect do
      snapshot(
        jobs:,
        step_job_ids: { child: 'job_child' },
        approval_decisions_by_job_id: { 'job_child' => { state: 123, decided_at: captured_at } }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'approval decision state must be :approved or :rejected')

    expect do
      snapshot(
        jobs:,
        step_job_ids: { child: 'job_child' },
        approval_decisions_by_job_id: { 'job_child' => { state: :rejected, decided_at: captured_at } }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'approval decision :rejected must include :reason')

    expect do
      snapshot(
        jobs:,
        step_job_ids: { child: 'job_child' },
        approval_decisions_by_job_id: { 'job_child' => { state: :rejected, decided_at: captured_at, reason: '   ' } }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'approval_rejection_reason must be present')

    expect do
      snapshot(
        jobs:,
        step_job_ids: { child: 'job_child' },
        approval_decisions_by_job_id: { 'job_child' => { state: :rejected, decided_at: captured_at, reason: 123 } }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'approval_rejection_reason must be a String')

    expect do
      snapshot(
        jobs:,
        step_job_ids: { child: 'job_child' },
        approval_decisions_by_job_id: {
          ' job_child ' => { state: :approved, decided_at: captured_at },
          job_child: { state: :approved, decided_at: captured_at }
        }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'duplicate approval decision job "job_child"')
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
