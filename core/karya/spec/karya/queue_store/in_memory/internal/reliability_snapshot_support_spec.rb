# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::ReliabilitySnapshotSupport' do
  subject(:store) { store_class.new }

  let(:store_class) { Karya::QueueStore::InMemory }
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }
  let(:policy) do
    Karya::CircuitBreaker::Policy.new(
      scope: { kind: :queue, value: 'billing' },
      failure_threshold: 2,
      window: 60,
      cooldown: 30,
      half_open_limit: 2
    )
  end

  def store_state
    store.instance_variable_get(:@state)
  end

  it 'reports remaining probe slots in half-open state' do
    store_state.breaker_states_by_scope['queue:billing'] = { state: :half_open, cooldown_until: nil }.freeze
    store_state.half_open_probe_admissions_by_scope['queue:billing'] = ['lease-1']
    store_state.reservations_by_token['lease-1'] = Karya::Reservation.new(
      token: 'lease-1',
      job_id: 'job-1',
      queue: 'billing',
      worker_id: 'worker-1',
      reserved_at: created_at + 1,
      expires_at: created_at + 31
    )

    expect(store.send(:probe_slots_remaining, 'queue:billing', policy, :half_open)).to eq(1)
  end

  it 'omits stuck-job entries when the job no longer exists' do
    store_state.stuck_job_recoveries_by_id['job-1'] = {
      recovery_count: 1,
      last_recovered_at: created_at + 1,
      last_recovery_reason: 'running_lease_expired'
    }.freeze

    expect(store.send(:snapshot_stuck_jobs)).to eq({})
  end

  it 'does not count breaker-blocked jobs when the configured breaker is closed' do
    store = store_class.new(
      circuit_breaker_policy_set: Karya::CircuitBreaker::PolicySet.new(
        policies: {
          'queue:billing' => {
            failure_threshold: 1,
            window: 60,
            cooldown: 30
          }
        }
      )
    )
    job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      state: :queued,
      created_at:
    )
    counts = Hash.new(0)

    store.send(:increment_breaker_blocked_counts, counts, job, created_at + 1)

    expect(counts).to eq({})
  end
end
