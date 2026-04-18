# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::RetryPolicySet do
  let(:supported_key_message) do
    'unsupported retry policy attribute; supported keys are: ' \
      'max_attempts, base_delay, multiplier, max_delay, jitter_strategy, escalate_on'
  end

  describe '#initialize' do
    it 'normalizes named retry policies from hashes and instances' do
      timeout_policy = Karya::RetryPolicy.new(max_attempts: 5, base_delay: 3, multiplier: 2)

      policy_set = described_class.new(
        policies: {
          timeout: { 'max_attempts' => 3, 'base_delay' => 5, 'multiplier' => 2, 'jitter_strategy' => 'full' },
          'slow-lane' => timeout_policy
        }
      )

      expect(policy_set.policy_for(:timeout)).to be_a(Karya::RetryPolicy)
      expect(policy_set.policy_for(:timeout).max_attempts).to eq(3)
      expect(policy_set.policy_for(:timeout).jitter_strategy).to eq(:full)
      expect(policy_set.policy_for('slow-lane')).to be(timeout_policy)
      expect(policy_set.policies).to be_frozen
      expect(policy_set).to be_frozen
    end

    it 'rejects duplicate keys after normalization' do
      expect do
        described_class.new(
          policies: {
            slow: { max_attempts: 3, base_delay: 5, multiplier: 2 },
            ' slow ' => { max_attempts: 4, base_delay: 6, multiplier: 2 }
          }
        )
      end.to raise_error(Karya::InvalidRetryPolicyError, 'duplicate retry policy key "slow" after normalization')
    end

    it 'rejects invalid source types' do
      expect do
        described_class.new(policies: [])
      end.to raise_error(Karya::InvalidRetryPolicyError, 'retry policies must be a Hash')
    end

    it 'rejects invalid policy values' do
      expect do
        described_class.new(policies: { fast: 42 })
      end.to raise_error(Karya::InvalidRetryPolicyError, 'retry policy must be built from a Hash or Karya::RetryPolicy')
    end

    it 'rejects malformed retry policy hashes' do
      expect do
        described_class.new(policies: { fast: { base_delay: 5, multiplier: 2 } })
      end.to raise_error(Karya::InvalidRetryPolicyError, 'retry policy must be built from a Hash or Karya::RetryPolicy')
    end

    it 'rejects invalid retry policy attribute keys' do
      expect do
        described_class.new(policies: { fast: { Object.new => 3, base_delay: 5, multiplier: 2 } })
      end.to raise_error(Karya::InvalidRetryPolicyError, supported_key_message)
    end

    it 'rejects unknown string retry policy attribute keys' do
      expect do
        described_class.new(policies: { fast: { 'unknown' => 3, base_delay: 5, multiplier: 2, max_attempts: 2 } })
      end.to raise_error(Karya::InvalidRetryPolicyError, supported_key_message)
    end

    it 'rejects unknown symbol retry policy attribute keys' do
      expect do
        described_class.new(policies: { fast: { unknown: 3, base_delay: 5, multiplier: 2, max_attempts: 2 } })
      end.to raise_error(Karya::InvalidRetryPolicyError, supported_key_message)
    end

    it 'returns nil for nil lookup keys' do
      policy_set = described_class.new(policies: {})

      expect(policy_set.policy_for(nil)).to be_nil
    end

    it 'rejects non-string non-symbol lookup keys' do
      policy_set = described_class.new(policies: {})

      expect do
        policy_set.policy_for(Object.new)
      end.to raise_error(Karya::InvalidRetryPolicyError, 'retry_policy lookup key must be a String or Symbol')
    end
  end
end
