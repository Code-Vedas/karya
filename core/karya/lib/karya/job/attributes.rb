# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../internal/failure_classification'
require_relative '../internal/retry_policy_resolver'
require_relative '../backpressure'
require_relative '../primitives/identifier'
require_relative '../primitives/lifecycle'
require_relative '../primitives/positive_finite_number'

module Karya
  class Job
    # Normalizes constructor input without leaking validation helpers onto the public job API.
    class Attributes
      VALID_UNIQUENESS_SCOPES = %i[queued active until_terminal].freeze
      VALID_UNIQUENESS_SCOPE_STRINGS = {
        'queued' => :queued,
        'active' => :active,
        'until_terminal' => :until_terminal
      }.freeze
      MAX_DEAD_LETTER_REASON_LENGTH = 1024

      def initialize(attributes)
        @attributes = attributes
      end

      def to_h
        created_at = normalize_created_at
        lifecycle = normalize_lifecycle
        normalized_attempt = normalize_attempt
        normalized_priority = normalize_priority

        normalized_attributes(
          created_at:,
          lifecycle:,
          attempt: normalized_attempt,
          priority: normalized_priority
        )
      end

      private

      attr_reader :attributes

      def required(name)
        attributes.fetch(name)
      rescue KeyError
        raise InvalidJobAttributeError, "#{name} must be present"
      end

      def optional(name, default)
        attributes.fetch(name, default)
      end

      def normalized_attributes(created_at:, lifecycle:, attempt:, priority:)
        normalized_queue = Primitives::Identifier.new(:queue, required(:queue), error_class: InvalidJobAttributeError).normalize
        normalized_handler = Primitives::Identifier.new(:handler, required(:handler), error_class: InvalidJobAttributeError).normalize

        {
          id: Primitives::Identifier.new(:id, required(:id), error_class: InvalidJobAttributeError).normalize,
          queue: normalized_queue,
          handler: normalized_handler,
          arguments: ImmutableArguments.new(optional(:arguments, {})).normalize,
          priority:,
          concurrency_scope: normalize_optional_scope(:concurrency_scope, :concurrency_key, queue: normalized_queue, handler: normalized_handler),
          rate_limit_scope: normalize_optional_scope(:rate_limit_scope, :rate_limit_key, queue: normalized_queue, handler: normalized_handler),
          retry_policy: normalize_retry_policy,
          execution_timeout: normalize_optional_positive_finite_number(:execution_timeout),
          expires_at: normalize_optional_time(:expires_at),
          idempotency_key: normalize_optional_identifier(:idempotency_key),
          uniqueness_key: normalize_optional_identifier(:uniqueness_key),
          uniqueness_scope: normalize_uniqueness_scope,
          lifecycle:,
          state: lifecycle.normalize_state(required(:state)),
          attempt:,
          created_at:,
          updated_at: normalize_updated_at(created_at),
          next_retry_at: normalize_optional_time(:next_retry_at),
          failure_classification: normalize_failure_classification,
          dead_letter_reason: normalize_dead_letter_reason,
          dead_lettered_at: normalize_optional_time(:dead_lettered_at),
          dead_letter_source_state: normalize_dead_letter_source_state(lifecycle)
        }
      end

      def normalize_attempt
        attempt = optional(:attempt, 0)
        raise InvalidJobAttributeError, 'attempt must be a non-negative Integer' unless attempt.is_a?(Integer) && attempt >= 0

        attempt
      end

      def normalize_priority
        priority = optional(:priority, 0)
        raise InvalidJobAttributeError, 'priority must be an Integer' unless priority.is_a?(Integer)

        priority
      end

      def normalize_created_at
        TimestampNormalizer.new(:created_at, required(:created_at)).normalize
      end

      def normalize_updated_at(created_at)
        TimestampNormalizer.new(:updated_at, optional(:updated_at, created_at)).normalize
      end

      def normalize_optional_time(name)
        optional(name, nil)&.then do |value|
          TimestampNormalizer.new(name, value).normalize
        end
      end

      def normalize_lifecycle
        Primitives::Lifecycle.new(
          :lifecycle,
          optional(:lifecycle, JobLifecycle.default_registry),
          error_class: InvalidJobAttributeError
        ).normalize
      end

      def normalize_optional_positive_finite_number(name)
        optional(name, nil)&.then do |value|
          Primitives::PositiveFiniteNumber.new(name, value, error_class: InvalidJobAttributeError).normalize
        end
      end

      def normalize_optional_identifier(name)
        optional(name, nil)&.then do |value|
          Primitives::Identifier.new(name, value, error_class: InvalidJobAttributeError).normalize
        end
      end

      def normalize_optional_scope(scope_name, legacy_key_name, queue:, handler:)
        scope_input = optional(scope_name, nil)
        legacy_key_input = optional(legacy_key_name, nil)
        raise InvalidJobAttributeError, "provide only one of #{scope_name} or #{legacy_key_name}" if scope_input && legacy_key_input

        normalized_scope =
          if scope_input
            Backpressure::ScopeSupport.normalize_scope(scope_name, scope_input, error_class: InvalidJobAttributeError)
          elsif legacy_key_input
            Backpressure::ScopeSupport.normalize_scope(
              legacy_key_name,
              { kind: :custom, value: legacy_key_input },
              error_class: InvalidJobAttributeError
            )
          end

        validate_routing_scope(normalized_scope, queue:, handler:, scope_name:)
        normalized_scope
      end

      def validate_routing_scope(scope, queue:, handler:, scope_name:)
        return unless scope

        scope_kind = scope.kind
        scope_value = scope.value

        case scope_kind
        when :queue
          return if scope_value == queue

          raise InvalidJobAttributeError, "#{scope_name} queue scope must match job queue"
        when :handler
          return if scope_value == handler

          raise InvalidJobAttributeError, "#{scope_name} handler scope must match job handler"
        end
      end

      def normalize_retry_policy
        Internal::RetryPolicyResolver.new(
          optional(:retry_policy, nil),
          policy_set: optional(:retry_policies, nil),
          error_class: InvalidJobAttributeError
        ).normalize
      end

      def normalize_failure_classification
        optional(:failure_classification, nil)&.then do |value|
          Internal::FailureClassification.normalize(value, error_class: InvalidJobAttributeError)
        end
      end

      def normalize_dead_letter_reason
        optional(:dead_letter_reason, nil)&.then do |value|
          raise InvalidJobAttributeError, 'dead_letter_reason must be a String' unless value.is_a?(String)
          raise InvalidJobAttributeError, 'dead_letter_reason must be present' if value.empty?
          if value.length > MAX_DEAD_LETTER_REASON_LENGTH
            raise InvalidJobAttributeError, "dead_letter_reason must be at most #{MAX_DEAD_LETTER_REASON_LENGTH} characters"
          end

          value.dup.freeze
        end
      end

      def normalize_dead_letter_source_state(lifecycle)
        optional(:dead_letter_source_state, nil)&.then do |value|
          lifecycle.normalize_state(value)
        end
      end

      def normalize_uniqueness_scope
        uniqueness_scope = optional(:uniqueness_scope, nil)
        uniqueness_scope_class = uniqueness_scope.class
        return nil if uniqueness_scope_class <= NilClass

        uniqueness_key = optional(:uniqueness_key, nil)
        uniqueness_key_class = uniqueness_key.class
        raise InvalidJobAttributeError, 'uniqueness_scope requires uniqueness_key' if uniqueness_key_class <= NilClass

        normalize_uniqueness_scope_value(uniqueness_scope)
      end

      def normalize_uniqueness_scope_value(uniqueness_scope)
        normalized_scope =
          case uniqueness_scope
          when Symbol
            uniqueness_scope
          when String
            VALID_UNIQUENESS_SCOPE_STRINGS[uniqueness_scope]
          end

        return normalized_scope if VALID_UNIQUENESS_SCOPES.include?(normalized_scope)

        raise InvalidJobAttributeError, 'uniqueness_scope must be one of :queued, :active, or :until_terminal'
      end

      # Normalizes timestamps into frozen copies so jobs cannot mutate caller-owned Time objects.
      class TimestampNormalizer
        def initialize(name, value)
          @name = name
          @value = value
        end

        def normalize
          return value.dup.freeze if value.is_a?(Time)

          raise InvalidJobAttributeError, "#{name} must be a Time"
        end

        private

        attr_reader :name, :value
      end

      private_constant :TimestampNormalizer, :VALID_UNIQUENESS_SCOPES, :VALID_UNIQUENESS_SCOPE_STRINGS
    end
  end
end
