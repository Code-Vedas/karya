# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Fairness::Policy do
  it 'defaults to round-robin reservation fairness' do
    policy = described_class.new

    expect(policy.strategy).to eq(:round_robin)
    expect(policy).to be_frozen
  end

  it 'accepts supported strategy symbols and strings' do
    expect(described_class.new(strategy: :strict_order).strategy).to eq(:strict_order)
    expect(described_class.new(strategy: 'round_robin').strategy).to eq(:round_robin)
  end

  it 'rejects unsupported strategies' do
    expect do
      described_class.new(strategy: :weighted)
    end.to raise_error(Karya::Fairness::InvalidPolicyError, 'strategy must be one of :round_robin or :strict_order')
  end
end
