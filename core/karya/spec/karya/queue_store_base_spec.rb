# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore do
  subject(:store) { implementation.new }

  let(:implementation) do
    Class.new do
      include Karya::QueueStore::Base
    end
  end

  it 'requires enqueue to be implemented' do
    expect do
      store.enqueue(job: instance_double(Karya::Job), now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #enqueue/)
  end

  it 'requires enqueue_many to be implemented' do
    expect do
      store.enqueue_many(jobs: [instance_double(Karya::Job)], now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #enqueue_many/)
  end

  it 'requires batch_snapshot to be implemented' do
    expect do
      store.batch_snapshot(batch_id: 'batch-1', now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #batch_snapshot/)
  end

  it 'requires enqueue_workflow to be implemented' do
    expect do
      store.enqueue_workflow(
        definition: instance_double(Karya::Workflow::Definition),
        jobs_by_step_id: {},
        batch_id: 'batch-1',
        now: Time.utc(2026, 3, 27, 12, 0, 0)
      )
    end.to raise_error(NotImplementedError, /implement #enqueue_workflow/)
  end

  it 'requires reserve to be implemented' do
    expect do
      store.reserve(
        queues: ['billing'],
        handler_names: ['billing_sync'],
        worker_id: 'worker-1',
        lease_duration: 30,
        now: Time.utc(2026, 3, 27, 12, 0, 0)
      )
    end.to raise_error(NotImplementedError, /implement #reserve/)
  end

  it 'requires release to be implemented' do
    expect do
      store.release(reservation_token: 'lease-1', now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #release/)
  end

  it 'requires start_execution to be implemented' do
    expect do
      store.start_execution(reservation_token: 'lease-1', now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #start_execution/)
  end

  it 'requires complete_execution to be implemented' do
    expect do
      store.complete_execution(reservation_token: 'lease-1', now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #complete_execution/)
  end

  it 'requires fail_execution to be implemented' do
    expect do
      store.fail_execution(reservation_token: 'lease-1', now: Time.utc(2026, 3, 27, 12, 0, 0), failure_classification: :error)
    end.to raise_error(NotImplementedError, /implement #fail_execution/)
  end

  it 'requires retry_jobs to be implemented' do
    expect do
      store.retry_jobs(job_ids: ['job-1'], now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #retry_jobs/)
  end

  it 'requires cancel_jobs to be implemented' do
    expect do
      store.cancel_jobs(job_ids: ['job-1'], now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #cancel_jobs/)
  end

  it 'requires dead_letter_jobs to be implemented' do
    expect do
      store.dead_letter_jobs(job_ids: ['job-1'], now: Time.utc(2026, 3, 27, 12, 0, 0), reason: 'manual')
    end.to raise_error(NotImplementedError, /implement #dead_letter_jobs/)
  end

  it 'requires replay_dead_letter_jobs to be implemented' do
    expect do
      store.replay_dead_letter_jobs(job_ids: ['job-1'], now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #replay_dead_letter_jobs/)
  end

  it 'requires retry_dead_letter_jobs to be implemented' do
    expect do
      store.retry_dead_letter_jobs(
        job_ids: ['job-1'],
        now: Time.utc(2026, 3, 27, 12, 0, 0),
        next_retry_at: Time.utc(2026, 3, 27, 12, 5, 0)
      )
    end.to raise_error(NotImplementedError, /implement #retry_dead_letter_jobs/)
  end

  it 'requires discard_dead_letter_jobs to be implemented' do
    expect do
      store.discard_dead_letter_jobs(job_ids: ['job-1'], now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #discard_dead_letter_jobs/)
  end

  it 'requires pause_queue to be implemented' do
    expect do
      store.pause_queue(queue: 'billing', now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #pause_queue/)
  end

  it 'requires resume_queue to be implemented' do
    expect do
      store.resume_queue(queue: 'billing', now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #resume_queue/)
  end

  it 'requires recover_orphaned_jobs to be implemented' do
    expect do
      store.recover_orphaned_jobs(worker_id: 'worker-1', now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #recover_orphaned_jobs/)
  end

  it 'requires recover_in_flight to be implemented' do
    expect do
      store.recover_in_flight(now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #recover_in_flight/)
  end

  it 'requires expire_reservations to be implemented' do
    expect do
      store.expire_reservations(now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #expire_reservations/)
  end

  it 'requires expire_jobs to be implemented' do
    expect do
      store.expire_jobs(now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #expire_jobs/)
  end
end
