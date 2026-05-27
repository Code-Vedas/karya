# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Normalizes the closed failure taxonomy without symbolizing arbitrary input.
    module FailureClassification
      MESSAGE = 'failure_classification must be one of :error, :timeout, or :expired'
      LIST_MESSAGE = 'escalate_on must be an Array of failure classifications'

      def self.normalize(value, error_class:)
        case value
        when :error, 'error'
          :error
        when :timeout, 'timeout'
          :timeout
        when :expired, 'expired'
          :expired
        else
          raise error_class, MESSAGE
        end
      end

      def self.normalize_list(values, error_class:)
        raise error_class, LIST_MESSAGE unless values.is_a?(Array)

        values.map { |value| normalize(value, error_class:) }.uniq.freeze
      end
    end
  end
end
