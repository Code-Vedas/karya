# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'backpressure'
require_relative 'primitives/positive_finite_number'
require_relative 'primitives/positive_integer'

module Karya
  # Raised when circuit-breaker policy input is invalid.
  class InvalidCircuitBreakerPolicyError < Error; end

  # Canonical circuit-breaker policy types for unhealthy execution paths.
  module CircuitBreaker
    VALID_SCOPE_KINDS = %i[queue handler].freeze
    ATTRIBUTE_KEYS = {
      'failure_threshold' => :failure_threshold,
      'window' => :window,
      'cooldown' => :cooldown,
      'half_open_limit' => :half_open_limit
    }.freeze
    SUPPORTED_ATTRIBUTE_KEYS = ATTRIBUTE_KEYS.values.freeze
    INVALID_POLICY_MESSAGE = 'circuit-breaker policy must be built from a Hash or Karya::CircuitBreaker::Policy'
    INVALID_POLICY_ATTRIBUTE_KEY_MESSAGE =
      "unsupported circuit-breaker policy attribute; supported keys are: #{SUPPORTED_ATTRIBUTE_KEYS.join(', ')}".freeze
    INVALID_POLICY_KEY_MESSAGE = 'circuit-breaker key must be a Karya::Backpressure::Scope, Hash, String, or Symbol'
    INVALID_DUPLICATE_POLICY_ATTRIBUTE_KEY_MESSAGE =
      'duplicate circuit-breaker policy attribute key %s after normalization'

    module_function

    def normalize_scope(scope)
      normalized_scope = Backpressure::Scope.from(
        scope,
        default_kind: :custom,
        error_class: InvalidCircuitBreakerPolicyError,
        field_name: :scope
      )
      return normalized_scope if VALID_SCOPE_KINDS.include?(normalized_scope.kind)

      raise InvalidCircuitBreakerPolicyError, 'scope kind must be :queue or :handler'
    end

    # Immutable circuit-breaker policy for one queue or handler scope.
    class Policy
      attr_reader :cooldown, :failure_threshold, :half_open_limit, :key, :scope, :window

      def initialize(failure_threshold:, window:, cooldown:, scope:, half_open_limit: 1)
        @scope = CircuitBreaker.normalize_scope(scope)
        @key = @scope.key
        @failure_threshold = Primitives::PositiveInteger.new(
          :failure_threshold,
          failure_threshold,
          error_class: InvalidCircuitBreakerPolicyError
        ).normalize
        @window = Primitives::PositiveFiniteNumber.new(
          :window,
          window,
          error_class: InvalidCircuitBreakerPolicyError
        ).normalize
        @cooldown = Primitives::PositiveFiniteNumber.new(
          :cooldown,
          cooldown,
          error_class: InvalidCircuitBreakerPolicyError
        ).normalize
        @half_open_limit = Primitives::PositiveInteger.new(
          :half_open_limit,
          half_open_limit,
          error_class: InvalidCircuitBreakerPolicyError
        ).normalize
        freeze
      end
    end

    # Immutable registry of circuit-breaker policies keyed by normalized scope.
    class PolicySet
      attr_reader :policies

      def initialize(policies: {})
        raise InvalidCircuitBreakerPolicyError, 'circuit-breaker policies must be a Hash' unless policies.is_a?(Hash)

        @policies = policies.each_with_object({}) do |(key, raw_policy), normalized|
          normalized_policy = normalize_policy(key, raw_policy)
          normalized_key = normalized_policy.key
          if normalized.key?(normalized_key)
            raise InvalidCircuitBreakerPolicyError,
                  "duplicate circuit-breaker key #{normalized_key.inspect} after normalization"
          end

          normalized[normalized_key] = normalized_policy
        end.freeze

        freeze
      end

      # :reek:NilCheck
      def policy_for(key)
        case key
        when nil
          nil
        when Backpressure::Scope, Hash, String, Symbol
          policies[CircuitBreaker.normalize_scope(key).key]
        else
          raise InvalidCircuitBreakerPolicyError, INVALID_POLICY_KEY_MESSAGE
        end
      end

      private

      # :reek:FeatureEnvy
      def normalize_policy(key, raw_policy)
        normalized_scope = CircuitBreaker.normalize_scope(key)
        case raw_policy
        when Policy
          return raw_policy if raw_policy.key == normalized_scope.key

          Policy.new(
            scope: normalized_scope,
            failure_threshold: raw_policy.failure_threshold,
            window: raw_policy.window,
            cooldown: raw_policy.cooldown,
            half_open_limit: raw_policy.half_open_limit
          )
        when Hash
          Policy.new(scope: normalized_scope, **normalize_policy_attributes(raw_policy))
        else
          invalid_policy_error
        end
      rescue ArgumentError, TypeError
        invalid_policy_error
      end

      def normalize_policy_attributes(raw_policy)
        raw_policy.each_with_object({}) do |(attribute_key, value), normalized|
          normalized_attribute_key = normalize_attribute_key(attribute_key)
          if normalized.key?(normalized_attribute_key)
            raise InvalidCircuitBreakerPolicyError,
                  format(INVALID_DUPLICATE_POLICY_ATTRIBUTE_KEY_MESSAGE, normalized_attribute_key.inspect)
          end

          normalized[normalized_attribute_key] = value
        end
      end

      def normalize_attribute_key(attribute_key)
        return normalize_symbol_attribute_key(attribute_key) if attribute_key.is_a?(Symbol)
        return normalize_string_attribute_key(attribute_key) if attribute_key.is_a?(String)

        raise InvalidCircuitBreakerPolicyError, INVALID_POLICY_ATTRIBUTE_KEY_MESSAGE
      end

      def normalize_symbol_attribute_key(attribute_key)
        return attribute_key if SUPPORTED_ATTRIBUTE_KEYS.include?(attribute_key)

        raise InvalidCircuitBreakerPolicyError, INVALID_POLICY_ATTRIBUTE_KEY_MESSAGE
      end

      def normalize_string_attribute_key(attribute_key)
        ATTRIBUTE_KEYS.fetch(attribute_key)
      rescue KeyError
        raise InvalidCircuitBreakerPolicyError, INVALID_POLICY_ATTRIBUTE_KEY_MESSAGE
      end

      def invalid_policy_error
        raise InvalidCircuitBreakerPolicyError, INVALID_POLICY_MESSAGE
      end
    end
  end
end
