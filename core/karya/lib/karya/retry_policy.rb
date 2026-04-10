# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  # Raised when retry policy configuration is invalid.
  class InvalidRetryPolicyError < Error; end

  # Immutable retry policy for deterministic retry/backoff behavior.
  class RetryPolicy
    attr_reader :base_delay, :max_attempts, :max_delay, :multiplier

    def initialize(max_attempts:, base_delay:, multiplier:, max_delay: nil)
      @max_attempts = normalize_max_attempts(max_attempts)
      @base_delay = normalize_non_negative_numeric(:base_delay, base_delay)
      @multiplier = normalize_multiplier(multiplier)
      @max_delay = normalize_optional_max_delay(max_delay)

      freeze
    end

    def delay_for(attempt)
      normalized_attempt = normalize_attempt(attempt)
      delay = base_delay * (multiplier**(normalized_attempt - 1))
      return delay unless max_delay

      [delay, max_delay].min
    end

    def retry?(attempt)
      normalize_attempt(attempt) < max_attempts
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
  end
end
