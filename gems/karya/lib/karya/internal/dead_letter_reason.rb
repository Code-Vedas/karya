# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Shared dead-letter reason normalization for job attributes and store operations.
    module DeadLetterReason
      MAX_LENGTH = 1024

      module_function

      def normalize(value, error_class:)
        raise error_class, 'dead_letter_reason must be a String' unless value.is_a?(String)

        normalized_value = value.strip
        raise error_class, 'dead_letter_reason must be present' if normalized_value.empty?
        raise error_class, "dead_letter_reason must be at most #{MAX_LENGTH} characters" if normalized_value.length > MAX_LENGTH

        normalized_value.freeze
      end
    end
  end
end
