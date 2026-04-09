# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Backpressure::PolicySet do
  it 'normalizes hash input into immutable policy objects' do
    policy_set = described_class.new(
      concurrency: { account_sync: { limit: 2 } },
      rate_limits: { partner_api: { limit: 5, period: 60 } }
    )

    concurrency_policy = policy_set.concurrency_policy_for('account_sync')
    rate_limit_policy = policy_set.rate_limit_policy_for('partner_api')

    expect(concurrency_policy).to be_a(Karya::Backpressure::ConcurrencyPolicy)
    expect(concurrency_policy.limit).to eq(2)
    expect(rate_limit_policy).to be_a(Karya::Backpressure::RateLimitPolicy)
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
    policy = Karya::Backpressure::ConcurrencyPolicy.new(key: 'account_sync', limit: 2)

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

  it 'returns nil for missing lookup keys' do
    policy_set = described_class.new

    expect(policy_set.concurrency_policy_for(nil)).to be_nil
    expect(policy_set.rate_limit_policy_for(nil)).to be_nil
  end
end
