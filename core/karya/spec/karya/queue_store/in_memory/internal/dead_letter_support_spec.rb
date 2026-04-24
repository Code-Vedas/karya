# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::DeadLetterSupport' do
  let(:internal) { Karya::QueueStore::InMemory.const_get(:Internal, false).const_get(:DeadLetterSupport, false) }
  let(:job_transition_class) { internal.const_get(:JobTransition, false) }
  let(:snapshot_entry_class) { internal.const_get(:SnapshotEntry, false) }
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }
  let(:failed_job) do
    Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      state: :failed,
      created_at:,
      updated_at: created_at + 1,
      failure_classification: :error
    )
  end

  it 'builds dead-letter transitions with metadata' do
    dead_letter_job = job_transition_class.new(job: failed_job, now: created_at + 2).dead_letter('manual-isolation')

    expect(dead_letter_job.state).to eq(:dead_letter)
    expect(dead_letter_job.dead_letter_reason).to eq('manual-isolation')
    expect(dead_letter_job.dead_letter_source_state).to eq(:failed)
  end

  it 'builds snapshot entries with recovery actions' do
    dead_letter_job = job_transition_class.new(job: failed_job, now: created_at + 2).dead_letter('manual-isolation')

    snapshot = snapshot_entry_class.new(job: dead_letter_job).to_h

    expect(snapshot).to include(job_id: 'job-1', available_actions: %i[replay retry discard])
  end
end
