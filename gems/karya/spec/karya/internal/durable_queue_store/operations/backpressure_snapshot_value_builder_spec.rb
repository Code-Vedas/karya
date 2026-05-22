# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::Operations::BackpressureSnapshotValueBuilder do
  include_context 'with durable queue-store operations spec support'

  it 'builds concurrency and rate-limit snapshots from durable rows' do
    created_at = now - 5
    scoped_policy_set = Karya::Backpressure::PolicySet.new(
      concurrency: {
        'tenant:tenant-7' => Karya::Backpressure::ConcurrencyPolicy.new(limit: 1, scope: 'tenant:tenant-7')
      },
      rate_limits: {
        'tenant:tenant-7' => Karya::Backpressure::RateLimitPolicy.new(limit: 1, period: 60, scope: 'tenant:tenant-7')
      }
    )
    scoped_store = store_class.new(policy_set: scoped_policy_set, circuit_breaker_policy_set:, max_batch_size: 10)
    active_job = job(
      id: 'job-active',
      state: :reserved,
      queue: 'billing',
      created_at:,
      updated_at: created_at,
      concurrency_scope: Karya::Backpressure::Scope.new(kind: :tenant, value: 'tenant-7'),
      rate_limit_scope: Karya::Backpressure::Scope.new(kind: :tenant, value: 'tenant-7')
    )
    blocked_job = job(
      id: 'job-blocked',
      state: :queued,
      queue: 'billing',
      created_at: created_at + 1,
      updated_at: created_at + 1,
      concurrency_scope: Karya::Backpressure::Scope.new(kind: :tenant, value: 'tenant-7'),
      rate_limit_scope: Karya::Backpressure::Scope.new(kind: :tenant, value: 'tenant-7')
    )
    rows = empty_rows.merge(
      namespace:,
      jobs: [job_row(active_job), job_row(blocked_job)],
      queue_entries: [queue_entry_row(blocked_job)],
      reservations: [reservation_row(job: active_job, token: 'token-1', phase: :reserved)],
      policy_state: [
        policy_row(
          policy_kind: 'rate_limit_admissions',
          scope_kind: 'tenant',
          scope_value: 'tenant-7',
          state_payload: { 'timestamps' => [now - 10] }
        )
      ]
    )
    snapshot = described_class.new(
      store: scoped_store,
      rows:,
      jobs: {
        'job-active' => active_job,
        'job-blocked' => blocked_job
      },
      now:,
      operation: Karya::Internal::DurableQueueStore::Operations::BackpressureSnapshot.new(
        store: scoped_store,
        request: { now: },
        operation_name: :backpressure_snapshot
      )
    ).build

    expect(snapshot[:concurrency].fetch('tenant:tenant-7')).to include(limit: 1, active_count: 1, blocked_count: 1)
    expect(snapshot[:rate_limits].fetch('tenant:tenant-7')).to include(limit: 1, period: 60, window_count: 1, blocked_count: 1)
  end
end
