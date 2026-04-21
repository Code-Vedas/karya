# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::CircuitBreaker::PolicySet do
  it 'normalizes hash input into immutable policy objects' do
    policy_set = described_class.new(
      policies: {
        { kind: :queue, value: 'billing' } => {
          failure_threshold: 3,
          window: 60,
          cooldown: 30
        },
        'handler:billing_sync' => {
          'failure_threshold' => 2,
          'window' => 20,
          'cooldown' => 10,
          'half_open_limit' => 2
        }
      }
    )

    queue_policy = policy_set.policy_for(kind: :queue, value: 'billing')
    handler_policy = policy_set.policy_for('handler:billing_sync')

    expect(queue_policy).to be_a(Karya::CircuitBreaker::Policy)
    expect(queue_policy.key).to eq('queue:billing')
    expect(queue_policy.failure_threshold).to eq(3)
    expect(queue_policy.window).to eq(60)
    expect(queue_policy.cooldown).to eq(30)
    expect(queue_policy.half_open_limit).to eq(1)

    expect(handler_policy.key).to eq('handler:billing_sync')
    expect(handler_policy.half_open_limit).to eq(2)
    expect(policy_set.policies).to be_frozen
  end

  it 'rejects scopes outside queue and handler' do
    expect do
      described_class.new(
        policies: {
          { kind: :tenant, value: 'tenant-7' } => {
            failure_threshold: 2,
            window: 60,
            cooldown: 30
          }
        }
      )
    end.to raise_error(Karya::InvalidCircuitBreakerPolicyError, 'scope kind must be :queue or :handler')
  end

  it 'reuses matching policy instances without rebuilding them' do
    policy = Karya::CircuitBreaker::Policy.new(
      failure_threshold: 2,
      window: 60,
      cooldown: 30,
      scope: { kind: :queue, value: 'billing' }
    )

    policy_set = described_class.new(policies: { 'queue:billing' => policy })

    expect(policy_set.policy_for('queue:billing')).to equal(policy)
  end

  it 'rejects duplicate normalized policy keys' do
    expect do
      described_class.new(
        policies: {
          { kind: :queue, value: 'billing' } => {
            failure_threshold: 2,
            window: 60,
            cooldown: 30
          },
          ' queue:billing ' => {
            failure_threshold: 3,
            window: 60,
            cooldown: 30
          }
        }
      )
    end.to raise_error(Karya::InvalidCircuitBreakerPolicyError, /duplicate circuit-breaker key "queue:billing"/)
  end

  it 'rejects non-hash policy registries' do
    expect do
      described_class.new(policies: [])
    end.to raise_error(Karya::InvalidCircuitBreakerPolicyError, /circuit-breaker policies must be a Hash/)
  end

  it 'rejects unsupported policy attribute keys' do
    expect do
      described_class.new(
        policies: {
          'queue:billing' => {
            threshold: 2,
            window: 60,
            cooldown: 30
          }
        }
      )
    end.to raise_error(Karya::InvalidCircuitBreakerPolicyError, /unsupported circuit-breaker policy attribute/)
  end

  it 'retargets mismatched policy instances to the registry scope' do
    policy = Karya::CircuitBreaker::Policy.new(
      failure_threshold: 2,
      window: 60,
      cooldown: 30,
      scope: { kind: :queue, value: 'billing' }
    )

    policy_set = described_class.new(policies: { 'handler:billing_sync' => policy })

    expect(policy_set.policy_for('handler:billing_sync')&.key).to eq('handler:billing_sync')
  end

  it 'rejects invalid raw policy objects' do
    expect do
      described_class.new(
        policies: {
          'queue:billing' => Object.new
        }
      )
    end.to raise_error(Karya::InvalidCircuitBreakerPolicyError, /circuit-breaker policy must be built/)
  end

  it 'rejects malformed policy hashes that cannot build a policy' do
    expect do
      described_class.new(
        policies: {
          'queue:billing' => {
            failure_threshold: 2,
            window: 60
          }
        }
      )
    end.to raise_error(Karya::InvalidCircuitBreakerPolicyError, /circuit-breaker policy must be built/)
  end

  it 'returns nil for missing lookup keys and rejects invalid lookup key types' do
    policy_set = described_class.new

    expect(policy_set.policy_for(nil)).to be_nil

    expect do
      policy_set.policy_for(123)
    end.to raise_error(Karya::InvalidCircuitBreakerPolicyError, /circuit-breaker key must be/)
  end

  it 'rejects duplicate attribute keys after normalization' do
    expect do
      described_class.new(
        policies: {
          'queue:billing' => {
            failure_threshold: 2,
            'failure_threshold' => 3,
            window: 60,
            cooldown: 30
          }
        }
      )
    end.to raise_error(Karya::InvalidCircuitBreakerPolicyError, /duplicate circuit-breaker policy attribute key/)
  end

  it 'rejects unsupported attribute key types and unknown string keys' do
    expect do
      described_class.new(
        policies: {
          'queue:billing' => {
            1 => 2,
            window: 60,
            cooldown: 30,
            failure_threshold: 2
          }
        }
      )
    end.to raise_error(Karya::InvalidCircuitBreakerPolicyError, /unsupported circuit-breaker policy attribute/)

    expect do
      described_class.new(
        policies: {
          'queue:billing' => {
            'unknown' => 1,
            'failure_threshold' => 2,
            'window' => 60,
            'cooldown' => 30
          }
        }
      )
    end.to raise_error(Karya::InvalidCircuitBreakerPolicyError, /unsupported circuit-breaker policy attribute/)
  end
end
