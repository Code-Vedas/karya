# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Shared validation for optional retry policy collaborators.
    class RetryPolicyNormalizer
      def initialize(value, error_class:)
        @value = value
        @error_class = error_class
      end

      def normalize
        value&.then do |retry_policy|
          return retry_policy if retry_policy.is_a?(RetryPolicy)

          raise error_class, 'retry_policy must be a Karya::RetryPolicy'
        end
      end

      private

      attr_reader :error_class, :value
    end
  end
end
