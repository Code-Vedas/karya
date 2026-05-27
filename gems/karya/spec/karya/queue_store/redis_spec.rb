# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

RSpec.describe Karya::QueueStore::Redis, :integration do
  def submission_job(id:, created_at:, queue: 'billing', handler: 'ProcessInvoice', arguments: {}, **attributes)
    Karya::Job.new(
      id:,
      queue:,
      handler:,
      arguments:,
      state: :submission,
      created_at:,
      **attributes
    )
  end

  def delete_redis_namespace(redis_url:, namespace:)
    client = Redis.new(url: redis_url)
    keys = client.scan_each(match: "#{namespace}:*").to_a
    client.del(*keys) unless keys.empty?
  ensure
    client&.close
  end

  let(:redis_url) { ENV.fetch('KARYA_REDIS_URL') { ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0') } }
  let(:namespace) { "queue_store_redis_spec_#{SecureRandom.hex(6)}" }
  let(:store) { described_class.new(url: redis_url, namespace:) }
  let(:created_at) { Time.utc(2026, 5, 23, 12, 0, 0) }

  before do
    delete_redis_namespace(redis_url:, namespace:)
  end

  after do
    delete_redis_namespace(redis_url:, namespace:)
  end

  it 'enqueues, reserves, and completes execution through durable Redis rows' do
    queued_job = store.enqueue(job: submission_job(id: 'job-1', created_at:), now: created_at + 1)
    reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 2)
    running_job = store.start_execution(reservation_token: reservation.token, now: created_at + 3)
    succeeded_job = store.complete_execution(reservation_token: reservation.token, now: created_at + 4)

    expect(queued_job.state).to eq(:queued)
    expect(reservation.job_id).to eq('job-1')
    expect(running_job.state).to eq(:running)
    expect(succeeded_job.state).to eq(:succeeded)
  end

  it 'supports durable batch and reliability reads through Redis row families' do
    store.enqueue_many(
      jobs: [
        submission_job(id: 'job-1', created_at:),
        submission_job(id: 'job-2', created_at: created_at + 1)
      ],
      now: created_at + 1,
      batch_id: 'batch-1'
    )
    reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 2)
    store.start_execution(reservation_token: reservation.token, now: created_at + 2.5)

    batch_snapshot = store.batch_snapshot(batch_id: 'batch-1', now: created_at + 3)
    reliability_snapshot = store.reliability_snapshot(now: created_at + 5)

    expect(batch_snapshot.job_ids).to eq(%w[job-1 job-2])
    expect(reliability_snapshot[:stuck_jobs].fetch('job-1')).to include(
      recovery_count: 1,
      last_recovery_reason: 'running_lease_expired'
    )
  end

  it 'supports workflow enqueue, snapshot, and approval controls through Redis row families' do
    definition = Karya::Workflow.define(:approval_gate) do
      step :approve, handler: :approve, wait_for_approval: :manager_approved
    end

    store.enqueue_workflow(
      definition:,
      jobs_by_step_id: {
        approve: submission_job(id: 'job-approve', created_at:, handler: 'approve')
      },
      batch_id: :batch_one,
      now: created_at + 1
    )

    expect(store.workflow_snapshot(batch_id: :batch_one, now: created_at + 2).state).to eq(:awaiting_approval)
    store.deliver_workflow_signal(batch_id: :batch_one, signal: :manager_approved, payload: {}, now: created_at + 3)

    approved_snapshot = store.workflow_snapshot(batch_id: :batch_one, now: created_at + 4)
    expect(approved_snapshot.fetch_step(:approve)).to be_ready
    expect(store.workflow_history(batch_id: :batch_one, now: created_at + 5).entries.map(&:action)).to include('signal_delivered', 'approval_approved')
  end

  it 'rejects invalid values and memoizes redis connection details' do
    store = described_class.allocate

    expect do
      store.send(:normalize_url, '')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /non-empty String/)
    expect do
      store.send(:normalize_namespace, nil)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /non-empty String/)

    store.instance_variable_set(:@url, redis_url)
    store.instance_variable_set(:@namespace, namespace)
    redis_client = instance_double(Redis)
    allow(Redis).to receive(:new).with(url: redis_url).and_return(redis_client)
    allow(redis_client).to receive(:scan_each).with(match: "#{namespace}:*").and_return([])
    allow(redis_client).to receive(:close)

    expect(store.send(:redis_client)).to equal(redis_client)
    expect(store.send(:redis_client)).to equal(redis_client)
    expect(store.send(:lock_key)).to eq("#{namespace}:queue_store:lock")
    expect(store.send(:version_key)).to eq("#{namespace}:queue_store:version")
  end

  it 'rejects token_generator overrides before building the durable store' do
    expect do
      described_class.new(url: redis_url, token_generator: -> { 'x' })
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /managed internally/)
  end
end
