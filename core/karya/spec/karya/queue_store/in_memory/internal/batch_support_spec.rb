# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::BatchSupport' do
  subject(:store) { Karya::QueueStore::InMemory.new }

  let(:created_at) { Time.utc(2026, 4, 24, 12, 0, 0) }

  def submission_job(id)
    Karya::Job.new(id:, queue: :billing, handler: :sync_billing, state: :submission, created_at:)
  end

  it 'builds and stores owner-local batch state' do
    jobs = [submission_job('job_1'), submission_job('job_2')]

    batch = store.send(:build_enqueue_batch, batch_id: 'batch_1', jobs:, now: created_at)
    stored_batch = store.send(:store_batch, batch)

    expect(stored_batch).to eq(batch)
    expect(store.send(:fetch_batch, 'batch_1')).to eq(batch)
  end

  it 'raises workflow-domain errors for duplicate and missing batches' do
    jobs = [submission_job('job_1')]
    batch = store.send(:build_enqueue_batch, batch_id: 'batch_1', jobs:, now: created_at)
    store.send(:store_batch, batch)

    expect do
      store.send(:build_enqueue_batch, batch_id: 'batch_1', jobs:, now: created_at)
    end.to raise_error(Karya::Workflow::DuplicateBatchError, 'batch "batch_1" already exists')

    expect do
      store.send(:fetch_batch, 'missing')
    end.to raise_error(Karya::Workflow::UnknownBatchError, 'batch "missing" is not registered')
  end

  it 'rejects batch ids reserved for workflow rollback batches' do
    store.send(:state).register_workflow_rollback(
      batch_id: 'batch_1',
      rollback_batch_id: 'batch_1.rollback',
      reason: 'operator rollback',
      requested_at: created_at,
      compensation_job_ids: []
    )

    expect do
      store.send(:build_enqueue_batch, batch_id: 'batch_1.rollback', jobs: [submission_job('job_1')], now: created_at)
    end.to raise_error(Karya::Workflow::DuplicateBatchError, 'batch "batch_1.rollback" already exists')
  end

  it 'raises workflow-domain errors for batches with missing member jobs' do
    batch = Karya::Workflow::Batch.new(id: 'batch_1', job_ids: ['missing_job'], created_at:)
    store.send(:store_batch, batch)

    expect do
      store.batch_snapshot(batch_id: 'batch_1', now: created_at + 1)
    end.to raise_error(
      Karya::Workflow::InvalidBatchError,
      'batch "batch_1" member job "missing_job" is not registered'
    )
  end
end
