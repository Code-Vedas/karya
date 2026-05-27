# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::Operations::ReliabilitySnapshot do
  include_context 'with durable queue-store operations spec support'

  it 'applies recovery rows before rebuilding stuck-job metadata' do
    expired_job = job(id: 'job-expired', state: :queued, expires_at: now - 1)
    reserved_job = job(id: 'job-reserved', state: :reserved)
    running_job = job(id: 'job-running', state: :queued)
    recovery = {
      expired_jobs: [expired_job],
      recovered_reserved_jobs: [reserved_job],
      recovered_running_jobs: [running_job]
    }
    rows = {
      namespace:,
      jobs: [job_row(expired_job), job_row(reserved_job), job_row(running_job)],
      queue_entries: [],
      reservations: [],
      policy_state: []
    }
    reliability_snapshot = described_class.new(store:, request: { now: }, operation_name: :reliability_snapshot)

    recovered_rows = Karya::Internal::DurableQueueStore::Operations::RecoveredRowsApplier.new(
      namespace:,
      rows:,
      jobs: recovery.values_at(:expired_jobs, :recovered_reserved_jobs, :recovered_running_jobs).flatten
    ).apply

    expect(recovered_rows.fetch(:jobs).length).to eq(3)
    expect(reliability_snapshot.send(:apply_recovery_to_rows, rows, recovery).fetch(:jobs).length).to eq(3)
  end

  it 'tracks stuck-job recovery rows and half-open probe availability' do
    running_job = job(id: 'job-1', state: :queued, queue: 'billing')
    rows = {
      namespace:,
      jobs: [job_row(running_job)],
      queue_entries: [queue_entry_row(running_job)],
      reservations: [{ reservation_token: 'a' }, { reservation_token: 'b' }],
      policy_state: [
        policy_row(
          policy_kind: 'stuck_job_recovery',
          scope_kind: 'job',
          scope_value: 'job-1',
          state_payload: { recovery_count: 1, last_recovered_at: now - 60, last_recovery_reason: 'running_lease_expired' }
        ),
        policy_row(
          policy_kind: 'stuck_job_recovery',
          scope_kind: 'job',
          scope_value: 'missing',
          state_payload: { recovery_count: 1 }
        ),
        policy_row(
          policy_kind: 'half_open_probes',
          scope_kind: 'queue',
          scope_value: 'billing',
          state_payload: { 'reservation_tokens' => %w[a b] }
        ),
        policy_row(
          policy_kind: 'breaker_state',
          scope_kind: 'queue',
          scope_value: 'billing',
          state_payload: { state: :half_open }
        ),
        policy_row(
          policy_kind: 'breaker_failures',
          scope_kind: 'queue',
          scope_value: 'billing',
          state_payload: { 'timestamps' => [now - 10] }
        )
      ]
    }
    scoped_policy_set = Karya::CircuitBreaker::PolicySet.new(
      policies: {
        'queue:billing' => Karya::CircuitBreaker::Policy.new(
          failure_threshold: 3,
          window: 60,
          cooldown: 30,
          scope: 'queue:billing',
          half_open_limit: 3
        )
      }
    )
    scoped_store = store_class.new(policy_set:, circuit_breaker_policy_set: scoped_policy_set, max_batch_size: 10)
    snapshot = Karya::Internal::DurableQueueStore::Operations::CircuitBreakerSnapshotBuilder.new(
      store: scoped_store,
      rows:,
      jobs: { 'job-1' => running_job },
      now:,
      operation: described_class.new(store: scoped_store, request: { now: }, operation_name: :reliability_snapshot)
    ).to_h
    merged_rows = Karya::Internal::DurableQueueStore::Operations::StuckJobRecoveryMerger.new(
      rows:,
      recovered_running_jobs: [running_job],
      now:
    ).merge
    payload = Karya::Internal::DurableQueueStore::PayloadCodec.decode(
      merged_rows.fetch(:policy_state).find { |row| row.fetch(:scope_value) == 'job-1' }.fetch(:state_payload)
    )
    stuck_snapshot = Karya::Internal::DurableQueueStore::Operations::StuckJobsSnapshotBuilder.new(
      rows: merged_rows,
      jobs: { 'job-1' => running_job }
    ).to_h

    expect(snapshot.fetch('queue:billing')).to include(state: :half_open, blocked_count: 0, probe_slots_remaining: 1)
    expect(payload['recovery_count'] || payload[:recovery_count]).to eq(2)
    expect(stuck_snapshot.keys).to eq(['job-1'])
  end
end
