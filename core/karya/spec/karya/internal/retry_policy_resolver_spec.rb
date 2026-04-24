# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../../lib/karya/internal/retry_policy_resolver'

RSpec.describe Karya::Internal::RetryPolicyResolver do
  let(:policy) { Karya::RetryPolicy.new(max_attempts: 3, base_delay: 5, multiplier: 2) }

  it 'normalizes retry policy sets from hashes' do
    policy_set = described_class.normalize_policy_set({ fast: policy }, error_class: Karya::InvalidQueueStoreOperationError)

    expect(policy_set).to be_a(Karya::RetryPolicySet)
    expect(policy_set.policy_for(:fast)).to eq(policy)
  end

  it 'returns nil retry policy sets unchanged' do
    expect(described_class.normalize_policy_set(nil, error_class: Karya::InvalidQueueStoreOperationError)).to be_nil
  end

  it 'rejects invalid retry policy sets' do
    expect do
      described_class.normalize_policy_set('bad', error_class: Karya::InvalidQueueStoreOperationError)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /retry_policies must be a Hash or Karya::RetryPolicySet/)
  end

  it 'returns direct retry policies unchanged' do
    resolver = described_class.new(policy, error_class: Karya::InvalidQueueStoreOperationError)

    expect(resolver.normalize).to eq(policy)
  end

  it 'resolves named policies through the provided set' do
    resolver = described_class.new(:fast, policy_set: { fast: policy }, error_class: Karya::InvalidQueueStoreOperationError)

    expect(resolver.normalize).to eq(policy)
  end

  it 'requires retry policies for named references' do
    resolver = described_class.new(:fast, error_class: Karya::InvalidQueueStoreOperationError)

    expect { resolver.normalize }.to raise_error(Karya::InvalidQueueStoreOperationError, /retry_policy references require retry_policies/)
  end

  it 'rejects unknown named policies' do
    resolver = described_class.new(:missing, policy_set: { fast: policy }, error_class: Karya::InvalidQueueStoreOperationError)

    expect { resolver.normalize }.to raise_error(Karya::InvalidQueueStoreOperationError, /unknown retry policy :missing/)
  end
end
