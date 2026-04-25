# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::UniquenessSupport' do
  subject(:store) { store_class.new(token_generator: token_generator) }

  let(:store_class) { Karya::QueueStore::InMemory }
  let(:token_sequence) { %w[lease-1 lease-2 lease-3].each }
  let(:token_generator) { -> { token_sequence.next } }
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }

  around do |example|
    Karya::JobLifecycle.send(:clear_extensions!)
    example.run
    Karya::JobLifecycle.send(:clear_extensions!)
  end

  def submission_job(id:, created_at:, uniqueness_key: 'billing:account-42', uniqueness_scope: :active)
    Karya::Job.new(
      id:,
      queue: 'billing',
      handler: 'billing_sync',
      uniqueness_key:,
      uniqueness_scope:,
      state: :submission,
      created_at:
    )
  end

  it 'ignores accepted decisions when duplicate error raising is asked directly' do
    decision = store.uniqueness_decision(
      job: submission_job(id: 'job-1', created_at:),
      now: created_at + 1
    )

    expect(store.send(:raise_duplicate_enqueue_error, decision)).to be_nil
  end

  it 'stores jobs directly for owner-local uniqueness evaluation helpers' do
    Karya::JobLifecycle.register_state(:quarantine, terminal: true)
    Karya::JobLifecycle.register_transition(from: :retry_pending, to: 'quarantine')

    quarantined_job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      uniqueness_key: 'billing:account-42',
      uniqueness_scope: :until_terminal,
      state: 'quarantine',
      created_at:,
      updated_at: created_at + 1
    )

    store.send(:store_job, job: quarantined_job)

    expect do
      store.enqueue(job: submission_job(id: 'job-2', created_at: created_at + 1, uniqueness_scope: :until_terminal), now: created_at + 2)
    end.not_to raise_error
  end

  it 'does not run batch pruning from generic terminal job storage' do
    limited_store = store_class.new(completed_batch_retention_limit: 0)
    state = limited_store.send(:state)
    batch_job = Karya::Job.new(id: 'job-1', queue: 'billing', handler: 'billing_sync', state: :succeeded, created_at:)
    unrelated_job = Karya::Job.new(id: 'job-2', queue: 'billing', handler: 'billing_sync', state: :succeeded, created_at:)

    limited_store.send(:store_job, job: batch_job)
    state.batches_by_id['batch-1'] = Karya::Workflow::Batch.new(id: 'batch-1', job_ids: ['job-1'], created_at:)
    limited_store.send(:store_job, job: unrelated_job)

    expect(state.batches_by_id.keys).to eq(['batch-1'])
  end

  it 'can build a failed reentry conflict job when the current state allows failure' do
    running_job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      uniqueness_key: 'billing:account-42',
      uniqueness_scope: :active,
      state: :running,
      attempt: 1,
      created_at:,
      updated_at: created_at + 1
    )

    conflict_job = store.send(:reentry_conflict_job, running_job)

    expect(conflict_job.state).to eq(:failed)
    expect(conflict_job.failure_classification).to eq(:error)
  end

  it 'returns the original job for uniqueness evaluation when no effective-state time is provided' do
    queued_job =
      submission_job(id: 'job-1', uniqueness_scope: :queued, created_at:).transition_to(
        :queued,
        updated_at: created_at + 1
      )

    expect(store.send(:effective_uniqueness_job, queued_job, nil)).to eq(queued_job)
  end
end
