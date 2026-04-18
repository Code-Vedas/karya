# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../retry_policy_set'

module Karya
  module Internal
    # Shared resolution for optional retry policy references and registries.
    class RetryPolicyResolver
      def self.normalize_policy_set(value, error_class:)
        return value if value.is_a?(RetryPolicySet)
        return if value.nil?

        return RetryPolicySet.new(policies: value) if value.is_a?(Hash)

        raise error_class, 'retry_policies must be a Hash or Karya::RetryPolicySet'
      rescue InvalidRetryPolicyError => e
        raise error_class, e.message
      end

      def initialize(value, error_class:, policy_set: nil)
        @value = value
        @policy_set = self.class.normalize_policy_set(policy_set, error_class:)
        @error_class = error_class
      end

      def normalize
        return value if value.is_a?(RetryPolicy)
        return if value.nil?

        return resolve_named_policy(value) if value.is_a?(String) || value.is_a?(Symbol)

        raise error_class, 'retry_policy must be a Karya::RetryPolicy, String, or Symbol'
      end

      private

      attr_reader :error_class, :policy_set, :value

      def resolve_named_policy(reference)
        raise error_class, 'retry_policy references require retry_policies' unless policy_set

        policy = policy_set.policy_for(reference)
        return policy if policy

        raise error_class, "unknown retry policy #{reference.inspect}"
      rescue InvalidRetryPolicyError => e
        raise error_class, e.message
      end
    end
  end
end
