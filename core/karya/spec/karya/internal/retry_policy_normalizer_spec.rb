# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../../lib/karya/internal/retry_policy_normalizer'

RSpec.describe Karya::Internal::RetryPolicyNormalizer do
  let(:policy) { Karya::RetryPolicy.new(max_attempts: 3, base_delay: 5, multiplier: 2) }

  it 'returns retry policy instances unchanged' do
    expect(described_class.new(policy, error_class: Karya::InvalidQueueStoreOperationError).normalize).to eq(policy)
  end

  it 'allows nil retry policies' do
    expect(described_class.new(nil, error_class: Karya::InvalidQueueStoreOperationError).normalize).to be_nil
  end

  it 'rejects invalid retry policy values' do
    expect do
      described_class.new('bad-policy', error_class: Karya::InvalidQueueStoreOperationError).normalize
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /retry_policy must be a Karya::RetryPolicy/)
  end
end
