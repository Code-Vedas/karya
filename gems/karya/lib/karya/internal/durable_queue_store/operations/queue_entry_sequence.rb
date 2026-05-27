# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Allocates the next queue-local insertion sequence from durable queue rows.
        class QueueEntrySequence
          def initialize(queue_entries:, queue:)
            @queue_entries = queue_entries
            @queue = queue
          end

          attr_reader :queue_entries, :queue

          def next_value
            queue_rows = queue_entries.select { |row| row.fetch(:queue) == queue }
            queue_rows.map { |row| row.fetch(:insertion_sequence) }.max.to_i + 1
          end
        end
      end
    end
  end
end
