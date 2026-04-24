# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::BackpressureSnapshotSupport' do
  subject(:store) { store_class.new(token_generator: token_generator) }

  let(:store_class) { Karya::QueueStore::InMemory }
  let(:token_sequence) { %w[lease-1 lease-2].each }
  let(:token_generator) { -> { token_sequence.next } }
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }

  def submission_job(id:, queue:, created_at:, handler: 'billing_sync')
    Karya::Job.new(
      id:,
      queue:,
      handler:,
      state: :submission,
      created_at:
    )
  end

  it 'requires a block for active reservation iteration helpers' do
    store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)

    expect do
      store.send(:each_active_reservation)
    end.to raise_error(ArgumentError, 'each_active_reservation requires a block')

    expect do
      store.send(:each_queued_job)
    end.to raise_error(ArgumentError, 'each_queued_job requires a block')
  end

  it 'returns nil from active reservation iteration helpers' do
    store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
    store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

    expect(store.send(:each_active_reservation) { |_reservation| nil }).to be_nil
    expect(store.send(:each_queued_job) { |_job| nil }).to be_nil
  end
end
