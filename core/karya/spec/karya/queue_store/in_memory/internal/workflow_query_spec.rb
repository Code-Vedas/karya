# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::WorkflowSupport::WorkflowQuery' do
  let(:queried_at) { Time.utc(2026, 4, 26, 12, 0, 0) }
  let(:described_class) do
    internal = Karya::QueueStore::InMemory.const_get(:Internal, false)
    workflow_support = internal.const_get(:WorkflowSupport, false)
    workflow_support.const_get(:WorkflowQuery, false)
  end

  def snapshot(steps)
    instance_double(Karya::Workflow::Snapshot, steps:, state: :running)
  end

  def step(step_id, active: false, ready: false, blocked: false, prerequisite_states: {})
    instance_double(
      Karya::Workflow::StepSnapshot,
      step_id:,
      active?: active,
      ready?: ready,
      blocked?: blocked,
      prerequisite_states:
    )
  end

  it 'prefers active steps over ready queued work' do
    result = described_class.new(
      snapshot: snapshot([step('root', active: true), step('child', ready: true)]),
      query: 'current-steps',
      queried_at:
    ).to_result

    expect(result).to have_attributes(query: 'current-steps', value: ['root'])
  end

  it 'falls back to blocked steps when no active or ready work exists' do
    result = described_class.new(
      snapshot: snapshot([step('approve', blocked: true)]),
      query: 'current-step',
      queried_at:
    ).to_result

    expect(result).to have_attributes(query: 'current-step', value: 'approve')
  end

  it 'excludes dependency-blocked descendants from current blocked steps' do
    result = described_class.new(
      snapshot: snapshot(
        [
          step('approve', blocked: true),
          step('capture_payment', blocked: true, prerequisite_states: { 'job-approve' => :queued })
        ]
      ),
      query: 'current-steps',
      queried_at:
    ).to_result

    expect(result).to have_attributes(query: 'current-steps', value: ['approve'])
  end

  it 'rejects unsupported queries' do
    expect do
      described_class.new(snapshot: snapshot([]), query: 'unsupported', queried_at:).to_result
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'unsupported workflow query "unsupported"')

    query = described_class.new(snapshot: snapshot([]), query: 'state', queried_at:)
    allow(query).to receive(:normalized_query).and_return('unsupported')

    expect do
      query.to_result
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'unsupported workflow query "unsupported"')
  end
end
