# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::WorkflowBatchRecord do
  let(:created_at) { Time.utc(2026, 5, 22, 12, 0, 0) }
  let(:batch) { Karya::Workflow::Batch.new(id: 'batch-1', job_ids: %w[a b], created_at:, updated_at: created_at + 1) }
  let(:registration) do
    Karya::QueueStore::Internal::StoreState.const_get(:WorkflowRegistration, false).build(
      workflow_id: 'wf-1',
      step_job_ids: { 'first' => 'a', 'second' => 'b' },
      dependency_job_ids_by_job_id: {},
      approval_requirements_by_job_id: {},
      interaction_requirements_by_job_id: {},
      compensation_jobs_by_step_id: {},
      child_workflow_ids_by_step_id: {}
    )
  end

  def build_job(id, state)
    Karya::Job.new(id:, queue: 'billing', handler: id, state:, created_at:)
  end

  it 'reports failed, running, succeeded, cancelled, and completed workflow states' do
    {
      failed: { 'a' => build_job('a', :failed), 'b' => build_job('b', :succeeded) },
      running: { 'a' => build_job('a', :running), 'b' => build_job('b', :queued) },
      succeeded: { 'a' => build_job('a', :succeeded), 'b' => build_job('b', :succeeded) },
      cancelled: { 'a' => build_job('a', :cancelled), 'b' => build_job('b', :cancelled) },
      completed: { 'a' => build_job('a', :succeeded), 'b' => build_job('b', :cancelled) }
    }.each do |expected_state, jobs_by_id|
      row = described_class.new(
        namespace: 'tenant-a',
        batch:,
        registration:,
        jobs_by_id:
      ).to_h

      expect(row.fetch(:state)).to eq(expected_state.to_s)
    end
  end
end
