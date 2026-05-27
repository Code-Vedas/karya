# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

RSpec.describe Karya::QueueStore::MySQL, :integration do
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

  def close_store_connection(store)
    store.connection.close
  rescue StandardError
    nil
  end

  let(:url) { ENV.fetch('MYSQL_DATABASE_URL', 'mysql2://root:rootROOT!1@127.0.0.1:3306/mysql') }
  let(:namespace) { "queue_store_mysql_spec_#{SecureRandom.hex(6)}" }
  let(:store) { described_class.new(url:, namespace:) }
  let(:created_at) { Time.utc(2026, 5, 23, 12, 0, 0) }

  after do
    close_store_connection(store)
  end

  it 'runs the durable lifecycle through persisted MySQL rows' do
    queued_job = store.enqueue(job: submission_job(id: 'job-1', created_at:), now: created_at + 1)
    reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 2)
    running_job = store.start_execution(reservation_token: reservation.token, now: created_at + 3)
    succeeded_job = store.complete_execution(reservation_token: reservation.token, now: created_at + 4)

    expect(queued_job.state).to eq(:queued)
    expect(reservation.job_id).to eq('job-1')
    expect(running_job.state).to eq(:running)
    expect(succeeded_job.state).to eq(:succeeded)
  end

  it 'supports durable batch and reliability reads through MySQL rows' do
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

  it 'supports workflow enqueue, snapshot, and approval controls through MySQL rows' do
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
end
