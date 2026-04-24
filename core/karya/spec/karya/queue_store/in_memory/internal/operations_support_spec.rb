# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::OperationsSupport' do
  let(:internal) { Karya::QueueStore::InMemory.const_get(:Internal, false).const_get(:OperationsSupport, false) }
  let(:batch_duplicate_decision_class) { internal.const_get(:BatchDuplicateDecision, false) }
  let(:retry_candidate_class) { internal.const_get(:RetryCandidate, false) }
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }
  let(:store) { Karya::QueueStore::InMemory.new }
  let(:state) { store.instance_variable_get(:@state) }

  around do |example|
    Karya::JobLifecycle.send(:clear_extensions!)
    example.run
    Karya::JobLifecycle.send(:clear_extensions!)
  end

  it 'builds duplicate uniqueness decisions for in-batch conflicts' do
    job = Karya::Job.new(
      id: 'job-2',
      queue: 'billing',
      handler: 'billing_sync',
      uniqueness_key: 'billing:account-42',
      uniqueness_scope: :active,
      state: :submission,
      created_at:
    )
    accepted_job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      uniqueness_key: 'billing:account-42',
      uniqueness_scope: :active,
      state: :queued,
      created_at:,
      updated_at: created_at + 1
    )

    decision = batch_duplicate_decision_class.new(job:, now: created_at + 2).for(
      accepted_job:,
      uniqueness_conflict: true
    )

    expect(decision).to include(result: :duplicate_uniqueness_key, conflicting_job_id: 'job-1')
  end

  it 'builds queued retries from retry-pending jobs' do
    retry_pending_job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      state: :retry_pending,
      created_at:,
      updated_at: created_at + 1,
      next_retry_at: created_at + 2,
      failure_classification: :error
    )

    retried_job = retry_candidate_class.new(job: retry_pending_job, now: created_at + 3).to_job

    expect(retried_job.state).to eq(:queued)
    expect(retried_job.failure_classification).to be_nil
  end

  it 'leaves unsupported cancellation states unchanged during index cleanup' do
    lifecycle = Karya::JobLifecycle::StateManager.new
    Karya::JobLifecycle::Extension.register_state(:paused, state_manager: lifecycle)
    custom_job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      state: :paused,
      created_at:,
      lifecycle:
    )

    expect { store.send(:cleanup_cancelled_job_indexes, custom_job) }
      .not_to change(state, :expired_reservation_tokens)
  end

  it 'ignores missing queued, reserved, and running indexes during cancellation cleanup' do
    queued_job = Karya::Job.new(id: 'queued-job', queue: 'billing', handler: 'billing_sync', state: :queued, created_at:)
    reserved_job = Karya::Job.new(id: 'reserved-job', queue: 'billing', handler: 'billing_sync', state: :reserved, created_at:)
    running_job = Karya::Job.new(id: 'running-job', queue: 'billing', handler: 'billing_sync', state: :running, created_at:)

    expect { store.send(:delete_queued_job_id, queued_job) }.not_to raise_error
    expect { store.send(:cancel_reservation_for, reserved_job.id) }.not_to raise_error
    expect { store.send(:cancel_execution_for, running_job.id) }.not_to raise_error
  end
end
