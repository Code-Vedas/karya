# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    # Immutable result for one queue pause/resume control operation.
    class QueueControlResult
      attr_reader :action, :changed, :performed_at, :paused, :queue

      def initialize(action:, performed_at:, queue:, paused:, changed:)
        raise InvalidQueueStoreOperationError, 'action must be a Symbol' unless action.is_a?(Symbol)
        raise InvalidQueueStoreOperationError, 'performed_at must be a Time' unless performed_at.is_a?(Time)
        raise InvalidQueueStoreOperationError, 'queue must be a String' unless queue.is_a?(String)
        raise InvalidQueueStoreOperationError, 'paused must be a boolean' unless [true, false].include?(paused)
        raise InvalidQueueStoreOperationError, 'changed must be a boolean' unless [true, false].include?(changed)

        @action = action
        @performed_at = performed_at.dup.freeze
        @queue = queue
        @paused = paused
        @changed = changed

        freeze
      end
    end
  end
end
