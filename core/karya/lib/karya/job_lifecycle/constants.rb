# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module JobLifecycle
    # Canonical lifecycle constants
    module Constants
      SUBMISSION = :submission
      QUEUED = :queued
      RESERVED = :reserved
      RUNNING = :running
      SUCCEEDED = :succeeded
      FAILED = :failed
      RETRY_PENDING = :retry_pending
      CANCELLED = :cancelled

      STATES = [
        SUBMISSION,
        QUEUED,
        RESERVED,
        RUNNING,
        SUCCEEDED,
        FAILED,
        RETRY_PENDING,
        CANCELLED
      ].freeze

      TRANSITIONS = {
        SUBMISSION => [QUEUED].freeze,
        QUEUED => [RESERVED, CANCELLED].freeze,
        RESERVED => [RUNNING, QUEUED, CANCELLED].freeze,
        RUNNING => [QUEUED, SUCCEEDED, FAILED, CANCELLED].freeze,
        SUCCEEDED => [].freeze,
        FAILED => [RETRY_PENDING].freeze,
        RETRY_PENDING => [QUEUED, CANCELLED].freeze,
        CANCELLED => [].freeze
      }.freeze

      TERMINAL_STATES = [SUCCEEDED, CANCELLED].freeze
      EMPTY_TRANSITIONS = [].freeze
      CANONICAL_STATE_NAMES = STATES.map(&:to_s).freeze
      CANONICAL_TERMINAL_STATE_NAMES = TERMINAL_STATES.map(&:to_s).freeze
      CANONICAL_TRANSITION_NAMES = TRANSITIONS.transform_keys(&:to_s).transform_values do |next_states|
        next_states.map(&:to_s).freeze
      end.freeze
      MAX_STATE_NAME_LENGTH = 64
    end
  end
end
