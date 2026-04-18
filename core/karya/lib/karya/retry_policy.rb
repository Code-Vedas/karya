# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'digest'

require_relative 'internal/failure_classification'

module Karya
  # Raised when retry policy configuration is invalid.
  class InvalidRetryPolicyError < Error; end

  # Immutable retry policy for deterministic retry/backoff behavior.
  class RetryPolicy
    JITTER_STRATEGIES = %i[none full equal].freeze
    HASH_DENOMINATOR = 0xffff_ffff_ffff_ffff.to_f
    JITTER_STRATEGY_STRINGS = {
      'none' => :none,
      'full' => :full,
      'equal' => :equal
    }.freeze

    # Immutable retry-decision result derived from policy, attempt, and failure classification.
    class RetryDecision
      attr_reader :action, :delay, :reason

      def initialize(action:, delay:, reason:)
        @action = action
        @delay = delay
        @reason = reason
        freeze
      end
    end

    attr_reader :base_delay, :escalate_on, :jitter_strategy, :max_attempts, :max_delay, :multiplier

    def initialize(max_attempts:, base_delay:, multiplier:, max_delay: nil, jitter_strategy: :none, escalate_on: [])
      @max_attempts = normalize_max_attempts(max_attempts)
      @base_delay = normalize_non_negative_numeric(:base_delay, base_delay)
      @multiplier = normalize_multiplier(multiplier)
      @max_delay = normalize_optional_max_delay(max_delay)
      @jitter_strategy = normalize_jitter_strategy(jitter_strategy)
      @escalate_on = normalize_escalate_on(escalate_on)

      freeze
    end

    def delay_for(attempt)
      normalized_attempt = normalize_attempt(attempt)
      clamp_delay(raw_delay_for(normalized_attempt))
    end

    def retry?(attempt)
      normalize_attempt(attempt) < max_attempts
    end

    def decision_for(attempt:, failure_classification:, jitter_key:)
      normalized_attempt = normalize_attempt(attempt)
      normalized_failure_classification = Internal::FailureClassification.normalize(
        failure_classification,
        error_class: InvalidRetryPolicyError
      )
      normalized_jitter_key = normalize_jitter_key(jitter_key)

      return RetryDecision.new(action: :stop, delay: nil, reason: nil) if normalized_failure_classification == :expired

      return RetryDecision.new(action: :escalate, delay: nil, reason: :classification_escalated) if escalate_on.include?(normalized_failure_classification)

      return RetryDecision.new(action: :escalate, delay: nil, reason: :retry_exhausted) unless retry?(normalized_attempt)

      RetryDecision.new(
        action: :retry,
        delay: jittered_delay_for(normalized_attempt, normalized_jitter_key),
        reason: nil
      )
    end

    private

    def normalize_attempt(attempt)
      return attempt if attempt.is_a?(Integer) && attempt >= 1

      raise InvalidRetryPolicyError, 'attempt must be an Integer greater than or equal to 1'
    end

    def normalize_max_attempts(value)
      return value if value.is_a?(Integer) && value >= 1

      raise InvalidRetryPolicyError, 'max_attempts must be an Integer greater than or equal to 1'
    end

    def normalize_multiplier(value)
      return value if value.is_a?(Numeric) && value.finite? && value >= 1

      raise InvalidRetryPolicyError, 'multiplier must be a finite Numeric greater than or equal to 1'
    end

    def normalize_non_negative_numeric(name, value)
      return value if value.is_a?(Numeric) && value.finite? && value >= 0

      raise InvalidRetryPolicyError, "#{name} must be a finite Numeric greater than or equal to 0"
    end

    def normalize_optional_max_delay(value)
      value&.then do |max_delay|
        normalize_non_negative_numeric(:max_delay, max_delay)
      end
    end

    def normalize_jitter_strategy(value)
      normalized_value =
        case value
        when Symbol
          value
        when String
          JITTER_STRATEGY_STRINGS[value]
        end

      return normalized_value if JITTER_STRATEGIES.include?(normalized_value)

      raise InvalidRetryPolicyError, 'jitter_strategy must be one of :none, :full, or :equal'
    end

    def normalize_escalate_on(value)
      raise InvalidRetryPolicyError, 'escalate_on must be an Array of failure classifications' unless value.is_a?(Array)

      value.map { |failure_classification| normalize_failure_classification(failure_classification) }.uniq.freeze
    end

    def normalize_jitter_key(value)
      return value if value.is_a?(String) && !value.empty?

      if value.is_a?(Symbol)
        normalized_value = value.to_s
        return normalized_value unless normalized_value.empty?
      end

      raise InvalidRetryPolicyError, 'jitter_key must be a non-empty String or Symbol'
    end

    def raw_delay_for(attempt)
      base_delay * (multiplier**(attempt - 1))
    end

    def jittered_delay_for(attempt, jitter_key)
      delay = raw_delay_for(attempt)
      return clamp_delay(delay) if jitter_strategy == :none

      digest = Digest::SHA256.hexdigest("#{jitter_key}:#{attempt}")
      fraction = digest[0, 16].to_i(16) / HASH_DENOMINATOR
      delay_with_jitter =
        case jitter_strategy
        when :full
          delay * fraction
        when :equal
          half_delay = delay / 2.0
          half_delay + (half_delay * fraction)
        else
          delay
        end

      clamp_delay(delay_with_jitter)
    end

    def clamp_delay(delay)
      return delay unless max_delay

      [delay, max_delay].min
    end

    def normalize_failure_classification(value)
      Internal::FailureClassification.normalize(value, error_class: InvalidRetryPolicyError)
    end
  end
end
