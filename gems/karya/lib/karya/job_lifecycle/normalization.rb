# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'constants'
require_relative 'errors'

module Karya
  module JobLifecycle
    # State normalization helpers
    module Normalization
      module_function

      def normalize_state_name(state)
        source = state.to_s.strip.downcase
        raise_blank_state_error! if source.empty?

        normalized_value = +''
        has_content = false
        previous_was_separator = false

        source.each_char do |character|
          if lowercase_letter?(character) || digit?(character)
            normalized_value << character
            has_content = true
            previous_was_separator = false
            next
          end

          next if !has_content || previous_was_separator

          normalized_value << '_'
          previous_was_separator = true
        end

        normalized_value.chomp!('_')
        raise_blank_state_error! unless has_content
        if normalized_value.length > Constants::MAX_STATE_NAME_LENGTH
          raise InvalidJobStateError,
                "Invalid job state name format: #{state.inspect} exceeds #{Constants::MAX_STATE_NAME_LENGTH} characters"
        end

        normalized_value
      end

      def lowercase_letter?(character)
        character.between?('a', 'z')
      end

      def digit?(character)
        character.between?('0', '9')
      end

      def raise_blank_state_error!
        raise InvalidJobStateError, 'state must be present'
      end
    end
  end
end
