# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'primitives/identifier'
require_relative 'retry_policy'

module Karya
  # Immutable registry of named retry policies.
  class RetryPolicySet
    ATTRIBUTE_KEYS = {
      'max_attempts' => :max_attempts,
      'base_delay' => :base_delay,
      'multiplier' => :multiplier,
      'max_delay' => :max_delay,
      'jitter_strategy' => :jitter_strategy,
      'escalate_on' => :escalate_on
    }.freeze
    INVALID_POLICY_MESSAGE = 'retry policy must be built from a Hash or Karya::RetryPolicy'
    INVALID_POLICY_ATTRIBUTE_KEY_MESSAGE = 'retry policy attribute keys must be Symbols or Strings'

    attr_reader :policies

    def initialize(policies: {})
      raise InvalidRetryPolicyError, 'retry policies must be a Hash' unless policies.is_a?(Hash)

      @policies = policies.each_with_object({}) do |(key, raw_policy), normalized|
        normalized_key = normalize_policy_key(key)
        raise InvalidRetryPolicyError, "duplicate retry policy key #{normalized_key.inspect} after normalization" if normalized.key?(normalized_key)

        normalized[normalized_key] = normalize_policy(raw_policy)
      end.freeze

      freeze
    end

    def policy_for(key)
      key&.then { |present_key| policies[normalize_policy_key(present_key)] }
    end

    private

    # :reek:UtilityFunction
    def normalize_policy_key(key)
      Primitives::Identifier.new(:retry_policy, key, error_class: InvalidRetryPolicyError).normalize
    end

    # :reek:DuplicateMethodCall
    def normalize_policy(raw_policy)
      message = INVALID_POLICY_MESSAGE
      return raw_policy if raw_policy.is_a?(RetryPolicy)

      raise InvalidRetryPolicyError, message unless raw_policy.is_a?(Hash)

      RetryPolicy.new(**normalize_policy_attributes(raw_policy))
    rescue ArgumentError, TypeError
      raise InvalidRetryPolicyError, message
    end

    def normalize_policy_attributes(raw_policy)
      raw_policy.each_with_object({}) do |(attribute_key, value), normalized|
        normalized[normalize_attribute_key(attribute_key)] = value
      end
    end

    # :reek:FeatureEnvy
    def normalize_attribute_key(attribute_key)
      message = INVALID_POLICY_ATTRIBUTE_KEY_MESSAGE
      return attribute_key if attribute_key.is_a?(Symbol)

      if attribute_key.is_a?(String)
        normalized_key = ATTRIBUTE_KEYS[attribute_key]
        return normalized_key if normalized_key
      end

      raise InvalidRetryPolicyError, message
    end
  end
end
