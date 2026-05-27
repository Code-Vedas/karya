# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::WorkflowStepRecord do
  let(:created_at) { Time.utc(2026, 5, 23, 12, 0, 0) }
  let(:job) { Karya::Job.new(id: 'job-1', queue: 'billing', handler: 'sync', state: :queued, created_at:, updated_at: created_at + 5) }
  let(:registration) do
    Karya::QueueStore::Internal::StoreState.const_get(:WorkflowRegistration, false).build(
      workflow_id: 'wf-1',
      workflow_family: 'billing',
      workflow_version: 'v1',
      step_job_ids: { 'step-1' => 'job-1' },
      dependency_job_ids_by_job_id: { 'job-1' => %w[dep-1 dep-2] },
      approval_requirements_by_job_id: { 'job-1' => { name: 'approval-needed', 'approver' => 'ops' } },
      interaction_requirements_by_job_id: { 'job-1' => { kind: :signal, name: 'approve' } },
      compensation_jobs_by_step_id: { 'step-1' => 'compensate-1' },
      child_workflow_ids_by_step_id: { 'step-1' => 'child-1' }
    )
  end
  let(:rollback) do
    Struct.new(:rollback_batch_id, :reason, :requested_at, :compensation_job_ids).new(
      'rollback-1', 'manual', created_at + 10, ['compensate-1']
    )
  end
  let(:decision) { Struct.new(:to_snapshot_decision).new({ 'approved' => true, 'actor' => 'ops' }) }
  let(:state) do
    Class.new do
      attr_reader :workflow_rollbacks_by_batch_id

      def initialize(decision:, rollback:, interaction_received_at:, pause_requested_at:)
        @decision = decision
        @rollback = rollback
        @interaction_received_at = interaction_received_at
        @pause_requested_at = pause_requested_at
        @workflow_rollbacks_by_batch_id = { 'batch-1' => rollback }
      end

      def workflow_approval_decision_for(_job_id)
        @decision
      end

      def workflow_interaction_received_at(batch_id:, kind:, name:)
        return @interaction_received_at if batch_id == 'batch-1' && kind == :signal && name == 'approve'

        nil
      end

      def workflow_pause_requested_at(_batch_id)
        @pause_requested_at
      end
    end.new(
      decision:,
      rollback:,
      interaction_received_at: created_at + 20,
      pause_requested_at: created_at + 30
    )
  end
  let(:context) { described_class::Context.new(registration:, state:) }

  it 'serializes workflow step metadata, dependencies, and rollback payload' do
    row = described_class.new(namespace: 'tenant', batch_id: 'batch-1', step_id: 'step-1', job:, context:).to_h

    expect(row).to include(
      namespace: 'tenant',
      batch_id: 'batch-1',
      step_id: 'step-1',
      step_sequence: 1,
      job_id: 'job-1',
      state: 'queued',
      updated_at: created_at + 5
    )
    expect(Karya::Internal::DurableQueueStore::PayloadCodec.decode(row.fetch(:dependency_payload))).to eq(%w[dep-1 dep-2])
    expect(Karya::Internal::DurableQueueStore::PayloadCodec.decode(row.fetch(:metadata_payload))).to eq(
      'approval_decision' => { 'approved' => true, 'actor' => 'ops' },
      'approval_requirement' => { name: 'approval-needed', 'approver' => 'ops' },
      'interaction_requirement' => { kind: :signal, name: 'approve' },
      'interaction_received_at' => created_at + 20,
      'compensation_job_id' => 'compensate-1',
      'child_workflow_id' => 'child-1',
      'pause_requested_at' => created_at + 30,
      'rollback' => {
        'rollback_batch_id' => 'rollback-1',
        'reason' => 'manual',
        'requested_at' => created_at + 10,
        'compensation_job_ids' => ['compensate-1']
      }
    )
  end

  it 'uses empty dependency ids and nil metadata branches when the registration has no optional fields' do
    empty_registration = Karya::QueueStore::Internal::StoreState.const_get(:WorkflowRegistration, false).build(
      workflow_id: 'wf-1',
      step_job_ids: { 'step-1' => 'job-1' },
      dependency_job_ids_by_job_id: {},
      approval_requirements_by_job_id: {},
      interaction_requirements_by_job_id: {},
      compensation_jobs_by_step_id: {},
      child_workflow_ids_by_step_id: {}
    )
    empty_state = state.class.new(decision: nil, rollback: nil, interaction_received_at: nil, pause_requested_at: nil)

    row = described_class.new(
      namespace: 'tenant',
      batch_id: 'batch-1',
      step_id: 'step-1',
      job:,
      context: described_class::Context.new(registration: empty_registration, state: empty_state)
    ).to_h

    expect(Karya::Internal::DurableQueueStore::PayloadCodec.decode(row.fetch(:dependency_payload))).to eq([])
    expect(Karya::Internal::DurableQueueStore::PayloadCodec.decode(row.fetch(:metadata_payload))).to include(
      'approval_decision' => nil,
      'approval_requirement' => nil,
      'interaction_requirement' => nil,
      'interaction_received_at' => nil,
      'compensation_job_id' => nil,
      'child_workflow_id' => nil,
      'pause_requested_at' => nil,
      'rollback' => nil
    )
  end
end
