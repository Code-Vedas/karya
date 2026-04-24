# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::ReliabilitySupport' do
  subject(:store) { store_class.new(circuit_breaker_policy_set: policy_set) }

  let(:store_class) { Karya::QueueStore::InMemory }
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }
  let(:policy_set) do
    Karya::CircuitBreaker::PolicySet.new(
      policies: {
        'queue:billing' => { failure_threshold: 2, window: 60, cooldown: 30 }
      }
    )
  end

  def store_state
    store.instance_variable_get(:@state)
  end

  def queued_job
    Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      state: :queued,
      created_at:,
      updated_at: created_at + 1
    )
  end

  it 'ignores expired failures for breaker history' do
    store.send(:record_execution_failure, queued_job, :expired, created_at + 2)

    expect(store_state.breaker_failures_by_scope).to eq({})
  end

  it 'tracks counted failures for configured breaker scopes' do
    store.send(:record_execution_failure, queued_job, :error, created_at + 2)

    expect(store_state.breaker_failures_by_scope.fetch('queue:billing')).to eq([created_at + 2])
  end
end
