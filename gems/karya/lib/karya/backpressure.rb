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

    # Immutable scope descriptor for concurrency and rate-limit policies.
    class Scope
      VALID_KINDS = {
        :queue => :queue,
        :handler => :handler,
        :tenant => :tenant,
        :workflow => :workflow,
        :custom => :custom,
        'queue' => :queue,
        'handler' => :handler,
        'tenant' => :tenant,
        'workflow' => :workflow,
        'custom' => :custom
      }.freeze

      attr_reader :kind, :key, :value

      def self.from(input, default_kind: :custom, error_class: InvalidPolicyError, field_name: :scope)
        return input if input.is_a?(self)

        value_class = input.class

        if value_class <= NilClass
          raise error_class, "#{field_name} must be present"
        elsif value_class <= Hash
          new(
            kind: fetch_attribute(input, :kind, error_class:, field_name:),
            value: fetch_attribute(input, :value, error_class:, field_name:),
            error_class:
          )
        elsif value_class <= String || value_class <= Symbol
          parsed_scope_attributes = parse_key_string(input, default_kind:, field_name:, error_class:)
          new(**parsed_scope_attributes, error_class:)
        else
          raise error_class, "#{field_name} must be a Karya::Backpressure::Scope, Hash, String, or Symbol"
        end
      end

      def initialize(kind:, value:, error_class: InvalidPolicyError)
        @kind = normalize_kind(kind, error_class:)
        raise error_class, 'value must be a String or Symbol' unless value.is_a?(String) || value.is_a?(Symbol)

        @value = Primitives::Identifier.new(:value, value, error_class:).normalize
        @key = "#{@kind}:#{@value}".freeze
        freeze
      end

      def ==(other)
        case other
        when Scope
          other.key == key
        else
          false
        end
      end
      alias eql? ==

      def hash
        key.hash
      end

      def to_h
        { kind:, value: }
      end

      class << self
        private

        def fetch_attribute(input, name, error_class:, field_name:)
          return input.fetch(name) if input.key?(name)

          string_key = name.to_s
          return input.fetch(string_key) if input.key?(string_key)

          raise error_class, "#{field_name} must include #{name.inspect}"
        end

        def parse_key_string(input, default_kind:, field_name:, error_class:)
          normalized_input = Primitives::Identifier.new(field_name, input, error_class:).normalize
          kind_part, value_part = normalized_input.split(':', 2)
          parsed_kind = VALID_KINDS[kind_part]

          if parsed_kind && value_part && !value_part.empty?
            { kind: parsed_kind, value: value_part }
          else
            { kind: default_kind, value: normalized_input }
          end
        end
      end

      private

      def normalize_kind(kind, error_class:)
        normalized_kind = VALID_KINDS[kind]
        return normalized_kind if normalized_kind

        raise error_class, 'scope kind must be one of :queue, :handler, :tenant, :workflow, or :custom'
      end
    end

    # Shared scope-input resolvers.
    module ScopeSupport
      module_function

      def normalize_scope(name, value, default_kind: :custom, error_class: InvalidPolicyError)
        Scope.from(value, default_kind:, error_class:, field_name: name)
      rescue StandardError => e
        raise unless e.is_a?(error_class) || e.is_a?(InvalidPolicyError)

        message = e.message
        message = "#{name} must be present" if message == 'value must be present'
        raise error_class, message
      end
    end

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

        policy_class.new(scope: normalized_scope, **policy_attributes)
      rescue ArgumentError, TypeError
        raise InvalidPolicyError, "#{policy_class.name.split('::').last} must be built from a Hash or policy instance"
      end

      private

      attr_reader :key, :policy_class, :raw_policy

      def matching_policy_instance?
        raw_policy.is_a?(policy_class) && raw_policy.scope == normalized_scope
      end

      def policy_attributes
        return normalized_hash_attributes if raw_policy.is_a?(Hash)

        {}
      end

      def normalized_hash_attributes
        raw_policy.each_with_object({}) do |(attribute_key, value), normalized|
          normalized[normalize_attribute_key(attribute_key)] = value
        end
      end

      def normalized_scope
        @normalized_scope ||= ScopeSupport.normalize_scope(:key, key)
      end

      def normalize_attribute_key(attribute_key)
        case attribute_key
        when Symbol
          attribute_key
        when String
          attribute_key.to_sym
        else
          raise InvalidPolicyError, 'policy attribute keys must be Symbols or Strings'
        end
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
          reject_duplicate_policy_key(policy, normalized)
          normalized[policy.key] = policy
        end.freeze
      end

      private

      attr_reader :invalid_type_message, :policy_class, :source

      def reject_duplicate_policy_key(policy, normalized)
        normalized_key = policy.key
        return unless normalized.key?(normalized_key)

        raise InvalidPolicyError, "duplicate #{policy_label} key #{normalized_key.inspect} after normalization"
      end

      def policy_label
        policy_class.name.split('::').last
                    .delete_suffix('Policy')
                    .gsub(/([a-z0-9])([A-Z])/, '\1 \2')
                    .downcase
      end
    end

    # Immutable concurrency-cap policy keyed by a job concurrency group.
    class ConcurrencyPolicy
      attr_reader :key, :limit, :scope

      def initialize(limit:, scope: nil, key: nil)
        @scope = normalize_scope(scope, key)
        @key = @scope.key
        @limit = Normalizers.positive_integer(:limit, limit)
        freeze
      end

      private

      def normalize_scope(scope, key)
        raise InvalidPolicyError, 'provide only one of scope or key' if scope && key

        input = scope || key
        field_name = scope ? :scope : :key
        ScopeSupport.normalize_scope(field_name, input)
      end
    end

    # Immutable rolling-window rate-limit policy keyed by a job rate-limit group.
    class RateLimitPolicy
      attr_reader :key, :limit, :period, :scope

      def initialize(limit:, period:, scope: nil, key: nil)
        @scope = normalize_scope(scope, key)
        @key = @scope.key
        @limit = Normalizers.positive_integer(:limit, limit)
        @period = Normalizers.positive_period(period)
        freeze
      end

      private

      def normalize_scope(scope, key)
        raise InvalidPolicyError, 'provide only one of scope or key' if scope && key

        input = scope || key
        field_name = scope ? :scope : :key
        ScopeSupport.normalize_scope(field_name, input)
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
        return nil unless key

        if key.is_a?(String)
          normalized_key = Normalizers.identifier(:key, key)
          return concurrency[normalized_key] if concurrency.key?(normalized_key)
        end
        return concurrency[key.key] if key.is_a?(Scope)

        concurrency[ScopeSupport.normalize_scope(:key, key).key]
      end

      def rate_limit_policy_for(key)
        return nil unless key

        if key.is_a?(String)
          normalized_key = Normalizers.identifier(:key, key)
          return rate_limits[normalized_key] if rate_limits.key?(normalized_key)
        end
        return rate_limits[key.key] if key.is_a?(Scope)

        rate_limits[ScopeSupport.normalize_scope(:key, key).key]
      end
    end
  end
end
