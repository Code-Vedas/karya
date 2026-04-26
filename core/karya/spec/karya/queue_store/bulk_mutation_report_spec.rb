# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::BulkMutationReport do
  let(:performed_at) { Time.utc(2026, 4, 1, 12, 0, 0) }
  let(:job) { Karya::Job.new(id: 'job-1', queue: 'billing', handler: 'billing_sync', state: :queued, created_at: performed_at) }

  def build_report(**overrides)
    described_class.new(
      action: :retry_jobs,
      performed_at:,
      requested_job_ids: ['job-1'],
      changed_jobs: [job],
      skipped_jobs: [{ job_id: 'job-2', reason: :not_found, state: nil }],
      **overrides
    )
  end

  it 'freezes normalized report fields' do
    mutable_job_id = +'job-1'
    mutable_skipped_job_id = +'job-2'
    mutable_state = +'custom'
    report = build_report(
      requested_job_ids: [mutable_job_id],
      skipped_jobs: [{ job_id: mutable_skipped_job_id, reason: :not_found, state: mutable_state }]
    )
    mutable_job_id.replace('changed-job-1')
    mutable_skipped_job_id.replace('changed-job-2')
    mutable_state.replace('changed-state')

    expect(report).to have_attributes(
      action: :retry_jobs,
      requested_count: 1,
      requested_job_ids: ['job-1'],
      changed_jobs: [job],
      skipped_jobs: [{ job_id: 'job-2', reason: :not_found, state: 'custom' }]
    )
    expect(report).to be_frozen
    expect(report.requested_job_ids).to be_frozen
    expect(report.requested_job_ids.first).to be_frozen
    expect(report.changed_jobs).to be_frozen
    expect(report.skipped_jobs).to be_frozen
    expect(report.skipped_jobs.first).to be_frozen
    expect(report.skipped_jobs.first.fetch(:job_id)).to be_frozen
    expect(report.skipped_jobs.first.fetch(:state)).to be_frozen
  end

  it 'validates constructor inputs' do
    expect { build_report(action: 'retry_jobs') }.to raise_error(Karya::InvalidQueueStoreOperationError, /action/)
    expect { build_report(action: :unknown) }.to raise_error(Karya::InvalidQueueStoreOperationError, /action/)
    expect { build_report(performed_at: 'now') }.to raise_error(Karya::InvalidQueueStoreOperationError, /performed_at/)
    expect { build_report(requested_job_ids: 'job-1') }.to raise_error(Karya::InvalidQueueStoreOperationError, /requested_job_ids/)
    expect { build_report(requested_job_ids: [1]) }.to raise_error(Karya::InvalidQueueStoreOperationError, /requested_job_ids entries/)
    expect { build_report(changed_jobs: 'job-1') }.to raise_error(Karya::InvalidQueueStoreOperationError, /changed_jobs/)
    expect { build_report(changed_jobs: ['job-1']) }.to raise_error(Karya::InvalidQueueStoreOperationError, /changed_jobs entries/)
    expect { build_report(skipped_jobs: 'job-1') }.to raise_error(Karya::InvalidQueueStoreOperationError, /skipped_jobs/)
    expect { build_report(skipped_jobs: ['job-1']) }.to raise_error(Karya::InvalidQueueStoreOperationError, /skipped_jobs entries/)
    expect { build_report(skipped_jobs: [{ reason: :not_found }]) }.to raise_error(KeyError, /job_id/)
    expect { build_report(skipped_jobs: [{ job_id: 1, reason: :not_found }]) }.to raise_error(Karya::InvalidQueueStoreOperationError, /job_id/)
    expect { build_report(skipped_jobs: [{ job_id: 'job-2', reason: :unknown }]) }.to raise_error(Karya::InvalidQueueStoreOperationError, /reason/)
    expect { build_report(skipped_jobs: [{ job_id: 'job-2', reason: :not_found, state: 1 }]) }.to raise_error(Karya::InvalidQueueStoreOperationError, /state/)
  end

  it 'accepts workflow step control actions' do
    actions = %i[
      enqueue_child_workflow
      retry_workflow_steps
      dead_letter_workflow_steps
      replay_workflow_steps
      retry_dead_letter_workflow_steps
      discard_workflow_steps
      sync_child_workflows
    ]

    expect(actions.map { |action| build_report(action:).action }).to eq(actions)
  end
end
