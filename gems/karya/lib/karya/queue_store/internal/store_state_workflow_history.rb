# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    module Internal
      # Workflow history journal storage for StoreState.
      class StoreState
        # Owner-local append-only history journal keyed by workflow batch id.
        class WorkflowHistory
          EMPTY = [].freeze
          MAX_ENTRIES_PER_BATCH = 1_000
          private_constant :EMPTY, :MAX_ENTRIES_PER_BATCH

          def initialize
            @by_batch_id = {}
            @max_entries_per_batch = MAX_ENTRIES_PER_BATCH
          end

          def for_batch(batch_id)
            history = @by_batch_id[batch_id]
            return EMPTY unless history

            history.to_a
          end

          def append(batch_id:, entry:)
            current_history(batch_id).append(entry)
            entry
          end

          def delete_by_batch(batch_id)
            history = @by_batch_id.delete(batch_id)
            return EMPTY unless history

            history.to_a
          end

          private

          attr_reader :max_entries_per_batch

          def current_history(batch_id)
            @by_batch_id[batch_id] ||= BatchHistory.new(max_size: max_entries_per_batch)
          end

          # Owner-local bounded workflow-history buffer for one workflow batch.
          class BatchHistory
            def initialize(max_size:)
              @max_size = max_size
              @entries = []
              @to_a = EMPTY
            end

            def append(entry)
              entries << entry
              entries.shift if entries.length > max_size
              @to_a = nil
              self
            end

            def to_a
              @to_a ||= entries.dup.freeze
            end

            private

            attr_reader :entries, :max_size
          end
        end

        private_constant :WorkflowHistory
      end
    end
  end
end
