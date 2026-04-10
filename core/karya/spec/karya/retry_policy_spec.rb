# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::RetryPolicy do
  describe '#initialize' do
    it 'stores normalized retry policy fields' do
      policy = described_class.new(max_attempts: 3, base_delay: 5, multiplier: 2, max_delay: 12)

      expect(policy.max_attempts).to eq(3)
      expect(policy.base_delay).to eq(5)
      expect(policy.multiplier).to eq(2)
      expect(policy.max_delay).to eq(12)
      expect(policy).to be_frozen
    end

    it 'rejects invalid max_attempts' do
      expect do
        described_class.new(max_attempts: 0, base_delay: 5, multiplier: 2)
      end.to raise_error(Karya::InvalidRetryPolicyError, 'max_attempts must be an Integer greater than or equal to 1')
    end

    it 'rejects invalid base_delay' do
      expect do
        described_class.new(max_attempts: 3, base_delay: -1, multiplier: 2)
      end.to raise_error(Karya::InvalidRetryPolicyError, 'base_delay must be a finite Numeric greater than or equal to 0')
    end

    it 'rejects invalid multiplier' do
      expect do
        described_class.new(max_attempts: 3, base_delay: 5, multiplier: 0.5)
      end.to raise_error(Karya::InvalidRetryPolicyError, 'multiplier must be a finite Numeric greater than or equal to 1')
    end

    it 'rejects invalid max_delay' do
      expect do
        described_class.new(max_attempts: 3, base_delay: 5, multiplier: 2, max_delay: -1)
      end.to raise_error(Karya::InvalidRetryPolicyError, 'max_delay must be a finite Numeric greater than or equal to 0')
    end
  end

  describe '#delay_for' do
    it 'computes deterministic exponential backoff' do
      policy = described_class.new(max_attempts: 5, base_delay: 3, multiplier: 2)

      expect(policy.delay_for(1)).to eq(3)
      expect(policy.delay_for(2)).to eq(6)
      expect(policy.delay_for(3)).to eq(12)
    end

    it 'applies max_delay clamp' do
      policy = described_class.new(max_attempts: 5, base_delay: 3, multiplier: 3, max_delay: 20)

      expect(policy.delay_for(3)).to eq(20)
    end

    it 'rejects invalid attempt values' do
      policy = described_class.new(max_attempts: 5, base_delay: 3, multiplier: 2)

      expect { policy.delay_for(0) }
        .to raise_error(Karya::InvalidRetryPolicyError, 'attempt must be an Integer greater than or equal to 1')
    end
  end

  describe '#retry?' do
    it 'allows retry before max_attempts and stops at max_attempts' do
      policy = described_class.new(max_attempts: 3, base_delay: 1, multiplier: 2)

      expect(policy.retry?(1)).to be(true)
      expect(policy.retry?(2)).to be(true)
      expect(policy.retry?(3)).to be(false)
    end
  end
end
