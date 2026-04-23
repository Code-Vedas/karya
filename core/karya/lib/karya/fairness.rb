# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  # Fairness controls for queue reservation behavior.
  module Fairness
    # Raised when fairness policy input is invalid.
    class InvalidPolicyError < Error; end

    # Immutable reservation fairness policy.
    class Policy
      STRATEGIES = {
        round_robin: :round_robin,
        strict_order: :strict_order,
        'round_robin' => :round_robin,
        'strict_order' => :strict_order
      }.freeze

      attr_reader :strategy

      def initialize(strategy: :round_robin)
        @strategy = normalize_strategy(strategy)
        freeze
      end

      private

      def normalize_strategy(value)
        normalized_strategy = STRATEGIES[value]
        return normalized_strategy if normalized_strategy

        raise InvalidPolicyError, 'strategy must be one of :round_robin or :strict_order'
      end
    end
  end
end
