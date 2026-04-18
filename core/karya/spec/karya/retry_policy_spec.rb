# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::RetryPolicy do
  describe '#initialize' do
    it 'stores normalized retry policy fields' do
      policy = described_class.new(
        max_attempts: 3,
        base_delay: 5,
        multiplier: 2,
        max_delay: 12,
        jitter_strategy: :equal,
        escalate_on: %i[timeout error]
      )

      expect(policy.max_attempts).to eq(3)
      expect(policy.base_delay).to eq(5)
      expect(policy.multiplier).to eq(2)
      expect(policy.max_delay).to eq(12)
      expect(policy.jitter_strategy).to eq(:equal)
      expect(policy.escalate_on).to eq(%i[timeout error])
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

    it 'rejects invalid jitter_strategy' do
      expect do
        described_class.new(max_attempts: 3, base_delay: 5, multiplier: 2, jitter_strategy: :random)
      end.to raise_error(Karya::InvalidRetryPolicyError, 'jitter_strategy must be one of :none, :full, or :equal')
    end

    it 'rejects non-string non-symbol jitter_strategy values' do
      expect do
        described_class.new(max_attempts: 3, base_delay: 5, multiplier: 2, jitter_strategy: 123)
      end.to raise_error(Karya::InvalidRetryPolicyError, 'jitter_strategy must be one of :none, :full, or :equal')
    end

    it 'accepts string jitter_strategy values' do
      policy = described_class.new(max_attempts: 3, base_delay: 5, multiplier: 2, jitter_strategy: 'full')

      expect(policy.jitter_strategy).to eq(:full)
    end

    it 'rejects invalid escalate_on' do
      expect do
        described_class.new(max_attempts: 3, base_delay: 5, multiplier: 2, escalate_on: :timeout)
      end.to raise_error(Karya::InvalidRetryPolicyError, 'escalate_on must be an Array of failure classifications')
    end

    it 'deduplicates escalate_on values after normalization' do
      policy = described_class.new(max_attempts: 3, base_delay: 5, multiplier: 2, escalate_on: [:timeout, 'timeout'])

      expect(policy.escalate_on).to eq([:timeout])
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

  describe '#decision_for' do
    it 'returns a retry decision with no jitter when jitter_strategy is none' do
      policy = described_class.new(max_attempts: 3, base_delay: 3, multiplier: 2)

      decision = policy.decision_for(attempt: 2, failure_classification: :error, jitter_key: 'job-1')

      expect(decision.action).to eq(:retry)
      expect(decision.delay).to eq(6)
      expect(decision.reason).to be_nil
    end

    it 'applies deterministic full jitter bounded by the unclamped exponential delay' do
      policy = described_class.new(max_attempts: 4, base_delay: 10, multiplier: 2, jitter_strategy: :full)

      first_decision = policy.decision_for(attempt: 2, failure_classification: :error, jitter_key: 'job-1')
      second_decision = policy.decision_for(attempt: 2, failure_classification: :error, jitter_key: 'job-1')
      other_decision = policy.decision_for(attempt: 2, failure_classification: :error, jitter_key: 'job-2')

      expect(first_decision.action).to eq(:retry)
      expect(first_decision.delay).to be >= 0
      expect(first_decision.delay).to be <= 20
      expect(second_decision.delay).to eq(first_decision.delay)
      expect(other_decision.delay).not_to eq(first_decision.delay)
    end

    it 'applies deterministic equal jitter in the upper half of the delay range' do
      policy = described_class.new(max_attempts: 4, base_delay: 10, multiplier: 2, jitter_strategy: :equal)

      decision = policy.decision_for(attempt: 2, failure_classification: :error, jitter_key: 'job-1')

      expect(decision.action).to eq(:retry)
      expect(decision.delay).to be >= 10
      expect(decision.delay).to be <= 20
    end

    it 'clamps jittered delays with max_delay' do
      policy = described_class.new(max_attempts: 4, base_delay: 10, multiplier: 3, max_delay: 12, jitter_strategy: :equal)

      decision = policy.decision_for(attempt: 2, failure_classification: :error, jitter_key: 'job-1')

      expect(decision.delay).to be <= 12
    end

    it 'escalates configured failure classifications immediately' do
      policy = described_class.new(max_attempts: 4, base_delay: 10, multiplier: 2, escalate_on: [:timeout])

      decision = policy.decision_for(attempt: 1, failure_classification: :timeout, jitter_key: 'job-1')

      expect(decision.action).to eq(:escalate)
      expect(decision.delay).to be_nil
      expect(decision.reason).to eq(:classification_escalated)
    end

    it 'escalates when retry attempts are exhausted' do
      policy = described_class.new(max_attempts: 2, base_delay: 10, multiplier: 2)

      decision = policy.decision_for(attempt: 2, failure_classification: :error, jitter_key: 'job-1')

      expect(decision.action).to eq(:escalate)
      expect(decision.delay).to be_nil
      expect(decision.reason).to eq(:retry_exhausted)
    end

    it 'returns stop for expired failures' do
      policy = described_class.new(max_attempts: 3, base_delay: 10, multiplier: 2)

      decision = policy.decision_for(attempt: 1, failure_classification: :expired, jitter_key: 'job-1')

      expect(decision.action).to eq(:stop)
      expect(decision.delay).to be_nil
      expect(decision.reason).to be_nil
    end

    it 'rejects invalid jitter_key values' do
      policy = described_class.new(max_attempts: 3, base_delay: 10, multiplier: 2)

      expect do
        policy.decision_for(attempt: 1, failure_classification: :error, jitter_key: nil)
      end.to raise_error(Karya::InvalidRetryPolicyError, 'jitter_key must be a non-empty String or Symbol')
    end

    it 'accepts symbol jitter_key values' do
      policy = described_class.new(max_attempts: 3, base_delay: 10, multiplier: 2, jitter_strategy: :full)

      decision = policy.decision_for(attempt: 1, failure_classification: :error, jitter_key: :job1)

      expect(decision.action).to eq(:retry)
      expect(decision.delay).to be_between(0, 10)
    end

    it 'rejects empty symbol jitter_key values' do
      policy = described_class.new(max_attempts: 3, base_delay: 10, multiplier: 2)

      expect do
        policy.decision_for(attempt: 1, failure_classification: :error, jitter_key: :"")
      end.to raise_error(Karya::InvalidRetryPolicyError, 'jitter_key must be a non-empty String or Symbol')
    end

    it 'falls back safely if jitter_strategy is unexpected at runtime' do
      policy_class = Class.new(described_class) do
        def jitter_strategy = :unexpected
      end
      policy = policy_class.new(max_attempts: 3, base_delay: 10, multiplier: 2)

      decision = policy.decision_for(attempt: 1, failure_classification: :error, jitter_key: 'job-1')

      expect(decision.action).to eq(:retry)
      expect(decision.delay).to eq(10)
    end
  end
end
