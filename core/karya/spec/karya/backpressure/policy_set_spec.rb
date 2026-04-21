# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Backpressure::PolicySet do
  it 'normalizes hash input into immutable policy objects' do
    policy_set = described_class.new(
      concurrency: { account_sync: { limit: 2 } },
      rate_limits: { { kind: :handler, value: :partner_api } => { limit: 5, period: 60 } }
    )

    concurrency_policy = policy_set.concurrency_policy_for('account_sync')
    rate_limit_policy = policy_set.rate_limit_policy_for(Karya::Backpressure::Scope.new(kind: :handler, value: 'partner_api'))

    expect(concurrency_policy).to be_a(Karya::Backpressure::ConcurrencyPolicy)
    expect(concurrency_policy.scope).to eq(Karya::Backpressure::Scope.new(kind: :custom, value: 'account_sync'))
    expect(concurrency_policy.key).to eq('custom:account_sync')
    expect(concurrency_policy.limit).to eq(2)
    expect(rate_limit_policy).to be_a(Karya::Backpressure::RateLimitPolicy)
    expect(rate_limit_policy.scope).to eq(Karya::Backpressure::Scope.new(kind: :handler, value: 'partner_api'))
    expect(rate_limit_policy.key).to eq('handler:partner_api')
    expect(rate_limit_policy.limit).to eq(5)
    expect(rate_limit_policy.period).to eq(60)
    expect(policy_set.concurrency).to be_frozen
    expect(policy_set.rate_limits).to be_frozen
  end

  it 'rejects invalid concurrency limits' do
    expect do
      described_class.new(concurrency: { account_sync: { limit: 0 } })
    end.to raise_error(Karya::Backpressure::InvalidPolicyError, /limit must be a positive Integer/)
  end

  it 'reuses matching policy instances without rebuilding them' do
    policy = Karya::Backpressure::ConcurrencyPolicy.new(scope: { kind: :custom, value: 'account_sync' }, limit: 2)

    policy_set = described_class.new(concurrency: { account_sync: policy })

    expect(policy_set.concurrency_policy_for('account_sync')).to equal(policy)
  end

  it 'rejects non-hash, non-policy values' do
    expect do
      described_class.new(concurrency: { account_sync: Object.new })
    end.to raise_error(
      Karya::Backpressure::InvalidPolicyError,
      /ConcurrencyPolicy must be built from a Hash or policy instance/
    )
  end

  it 'normalizes string attribute keys for policy hashes' do
    policy_set = described_class.new(concurrency: { account_sync: { 'limit' => 2 } })

    expect(policy_set.concurrency_policy_for('account_sync')&.limit).to eq(2)
  end

  it 'accepts scope objects and scope hashes as registry keys' do
    queue_scope = Karya::Backpressure::Scope.new(kind: :queue, value: 'billing')
    policy_set = described_class.new(
      concurrency: {
        queue_scope => { limit: 2 },
        { 'kind' => 'tenant', 'value' => 'tenant-7' } => { limit: 1 }
      },
      rate_limits: {
        { kind: :handler, value: 'billing_sync' } => { limit: 5, period: 60 }
      }
    )

    expect(policy_set.concurrency_policy_for(queue_scope)&.key).to eq('queue:billing')
    expect(policy_set.concurrency_policy_for(kind: :tenant, value: 'tenant-7')&.key).to eq('tenant:tenant-7')
    expect(policy_set.rate_limit_policy_for(kind: :handler, value: 'billing_sync')&.key).to eq('handler:billing_sync')
  end

  it 'round-trips concurrency lookups by normalized policy key string' do
    policy_set = described_class.new(
      concurrency: {
        { kind: :custom, value: 'account_sync' } => { limit: 2 }
      }
    )

    expect(policy_set.concurrency_policy_for('custom:account_sync')&.limit).to eq(2)
    expect(policy_set.concurrency_policy_for(' custom:account_sync ')&.limit).to eq(2)
  end

  it 'round-trips rate-limit lookups by normalized policy key string' do
    policy_set = described_class.new(
      rate_limits: {
        { kind: :handler, value: 'billing_sync' } => { limit: 5, period: 60 }
      }
    )

    expect(policy_set.rate_limit_policy_for('handler:billing_sync')&.limit).to eq(5)
    expect(policy_set.rate_limit_policy_for(' handler:billing_sync ')&.limit).to eq(5)
  end

  it 'falls back from trimmed rate-limit string lookup to shorthand scope normalization' do
    policy_set = described_class.new(
      rate_limits: {
        partner_api: { limit: 5, period: 60 }
      }
    )

    expect(policy_set.rate_limit_policy_for(' partner_api ')&.key).to eq('custom:partner_api')
  end

  it 'rejects unsupported policy attribute key types' do
    expect do
      described_class.new(concurrency: { account_sync: { 1 => 2 } })
    end.to raise_error(Karya::Backpressure::InvalidPolicyError, /policy attribute keys must be Symbols or Strings/)
  end

  it 'rejects duplicate normalized policy keys' do
    expect do
      described_class.new(
        concurrency: {
          :account_sync => { limit: 1 },
          { kind: :custom, value: ' account_sync ' } => { limit: 2 }
        }
      )
    end.to raise_error(Karya::Backpressure::InvalidPolicyError, /duplicate concurrency key "custom:account_sync" after normalization/)
  end

  it 'rejects non-hash policy registries' do
    expect do
      described_class.new(concurrency: [])
    end.to raise_error(Karya::Backpressure::InvalidPolicyError, /concurrency policies must be a Hash/)
  end

  it 'rejects invalid rate-limit periods' do
    expect do
      described_class.new(rate_limits: { partner_api: { limit: 1, period: Float::INFINITY } })
    end.to raise_error(Karya::Backpressure::InvalidPolicyError, /period must be a positive finite number/)
  end

  it 'rejects non-finite bigdecimal periods' do
    expect do
      described_class.new(rate_limits: { partner_api: { limit: 1, period: BigDecimal('Infinity') } })
    end.to raise_error(Karya::Backpressure::InvalidPolicyError, /period must be a positive finite number/)
  end

  it 'returns nil for missing lookup keys' do
    policy_set = described_class.new

    expect(policy_set.concurrency_policy_for(nil)).to be_nil
    expect(policy_set.rate_limit_policy_for(nil)).to be_nil
  end

  it 'rejects invalid scope keys' do
    expect do
      described_class.new(concurrency: { { value: 'billing' } => { limit: 1 } })
    end.to raise_error(Karya::Backpressure::InvalidPolicyError, /key must include :kind/)
  end
end
