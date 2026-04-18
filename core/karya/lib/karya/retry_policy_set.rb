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
    SUPPORTED_ATTRIBUTE_KEYS = ATTRIBUTE_KEYS.values.freeze
    INVALID_POLICY_MESSAGE = 'retry policy must be built from a Hash or Karya::RetryPolicy'
    INVALID_POLICY_ATTRIBUTE_KEY_MESSAGE =
      "unsupported retry policy attribute; supported keys are: #{SUPPORTED_ATTRIBUTE_KEYS.join(', ')}".freeze
    INVALID_POLICY_KEY_MESSAGE = 'retry_policy key must be a String or Symbol'

    attr_reader :policies

    def initialize(policies: {})
      raise InvalidRetryPolicyError, 'retry policies must be a Hash' unless policies.is_a?(Hash)

      @policies = policies.each_with_object({}) do |(key, raw_policy), normalized|
        normalized_key =
          case key
          when String, Symbol
            Primitives::Identifier.new(:retry_policy, key, error_class: InvalidRetryPolicyError).normalize
          else
            raise InvalidRetryPolicyError, INVALID_POLICY_KEY_MESSAGE
          end
        raise InvalidRetryPolicyError, "duplicate retry policy key #{normalized_key.inspect} after normalization" if normalized.key?(normalized_key)

        normalized[normalized_key] = normalize_policy(raw_policy)
      end.freeze

      freeze
    end

    def policy_for(key)
      case key
      when String, Symbol
        policies[Primitives::Identifier.new(:retry_policy, key, error_class: InvalidRetryPolicyError).normalize]
      when nil
        nil
      else
        raise InvalidRetryPolicyError, 'retry_policy lookup key must be a String or Symbol'
      end
    end

    private

    def normalize_policy(raw_policy)
      case raw_policy
      when RetryPolicy
        raw_policy
      when Hash
        RetryPolicy.new(**normalize_policy_attributes(raw_policy))
      else
        invalid_policy_error
      end
    rescue ArgumentError, TypeError
      invalid_policy_error
    end

    def normalize_policy_attributes(raw_policy)
      raw_policy.each_with_object({}) do |(attribute_key, value), normalized|
        normalized[normalize_attribute_key(attribute_key)] = value
      end
    end

    def normalize_attribute_key(attribute_key)
      return normalize_symbol_attribute_key(attribute_key) if attribute_key.is_a?(Symbol)
      return normalize_string_attribute_key(attribute_key) if attribute_key.is_a?(String)

      raise InvalidRetryPolicyError, INVALID_POLICY_ATTRIBUTE_KEY_MESSAGE
    end

    def normalize_symbol_attribute_key(attribute_key)
      return attribute_key if SUPPORTED_ATTRIBUTE_KEYS.include?(attribute_key)

      raise InvalidRetryPolicyError, INVALID_POLICY_ATTRIBUTE_KEY_MESSAGE
    end

    def normalize_string_attribute_key(attribute_key)
      ATTRIBUTE_KEYS.fetch(attribute_key)
    rescue KeyError
      raise InvalidRetryPolicyError, INVALID_POLICY_ATTRIBUTE_KEY_MESSAGE
    end

    def invalid_policy_error
      raise InvalidRetryPolicyError, INVALID_POLICY_MESSAGE
    end
  end
end
