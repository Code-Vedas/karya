# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'bigdecimal'

require_relative 'primitives/identifier'
require_relative 'primitives/positive_finite_number'
require_relative 'primitives/positive_integer'

module Karya
  module Backpressure
    # Raised when backpressure policy input is invalid.
    class InvalidPolicyError < Error; end

    # Shared policy-input normalizers.
    module Normalizers
      module_function

      def identifier(name, value)
        Primitives::Identifier.new(name, value, error_class: InvalidPolicyError).normalize
      end

      def positive_integer(name, value)
        Primitives::PositiveInteger.new(name, value, error_class: InvalidPolicyError).normalize
      end

      def positive_period(value)
        normalized_value = Primitives::PositiveFiniteNumber.new(:period, value, error_class: InvalidPolicyError).normalize
        non_finite_decimal_or_float = [Float, BigDecimal].any? do |type|
          normalized_value.is_a?(type) && !normalized_value.finite?
        end
        raise InvalidPolicyError, 'period must be a positive finite number' if non_finite_decimal_or_float

        normalized_value
      end
    end

    # Builds policy instances from hash or instance input.
    class PolicyNormalizer
      def initialize(key, raw_policy, policy_class)
        @key = key
        @raw_policy = raw_policy
        @policy_class = policy_class
      end

      def normalize
        return raw_policy if matching_policy_instance?

        policy_class.new(key:, **policy_attributes)
      rescue ArgumentError
        raise InvalidPolicyError, "#{policy_class.name.split('::').last} must be built from a Hash or policy instance"
      end

      private

      attr_reader :key, :policy_class, :raw_policy

      def matching_policy_instance?
        raw_policy.is_a?(policy_class) && raw_policy.key == Normalizers.identifier(:key, key)
      end

      def policy_attributes
        return raw_policy if raw_policy.is_a?(Hash)

        {}
      end
    end

    # Normalizes policy registries into immutable keyed hashes.
    class PolicyHashNormalizer
      def initialize(source, policy_class, invalid_type_message)
        @source = source
        @policy_class = policy_class
        @invalid_type_message = invalid_type_message
      end

      def normalize
        raise InvalidPolicyError, invalid_type_message unless source.is_a?(Hash)

        source.each_with_object({}) do |(key, raw_policy), normalized|
          policy = PolicyNormalizer.new(key, raw_policy, policy_class).normalize
          normalized[policy.key] = policy
        end.freeze
      end

      private

      attr_reader :invalid_type_message, :policy_class, :source
    end

    # Immutable concurrency-cap policy keyed by a job concurrency group.
    class ConcurrencyPolicy
      attr_reader :key, :limit

      def initialize(key:, limit:)
        @key = Normalizers.identifier(:key, key)
        @limit = Normalizers.positive_integer(:limit, limit)
        freeze
      end
    end

    # Immutable fixed-window rate-limit policy keyed by a job rate-limit group.
    class RateLimitPolicy
      attr_reader :key, :limit, :period

      def initialize(key:, limit:, period:)
        @key = Normalizers.identifier(:key, key)
        @limit = Normalizers.positive_integer(:limit, limit)
        @period = Normalizers.positive_period(period)
        freeze
      end
    end

    # Immutable registry of concurrency and rate-limit policies.
    class PolicySet
      attr_reader :concurrency, :rate_limits

      def initialize(concurrency: {}, rate_limits: {})
        @concurrency = PolicyHashNormalizer.new(
          concurrency,
          ConcurrencyPolicy,
          'concurrency policies must be a Hash'
        ).normalize
        @rate_limits = PolicyHashNormalizer.new(
          rate_limits,
          RateLimitPolicy,
          'rate limit policies must be a Hash'
        ).normalize
        freeze
      end

      def concurrency_policy_for(key)
        key&.then { |present_key| concurrency[Normalizers.identifier(:key, present_key)] }
      end

      def rate_limit_policy_for(key)
        key&.then { |present_key| rate_limits[Normalizers.identifier(:key, present_key)] }
      end
    end
  end
end
