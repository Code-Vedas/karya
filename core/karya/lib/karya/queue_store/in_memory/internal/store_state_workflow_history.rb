# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Owner-local workflow history journal storage for StoreState.
        class StoreState
          # Owner-local append-only history journal keyed by workflow batch id.
          class WorkflowHistory
            EMPTY = [].freeze
            private_constant :EMPTY

            def initialize
              @by_batch_id = {}
            end

            def for_batch(batch_id)
              entries = @by_batch_id[batch_id]
              return EMPTY unless entries

              entries.dup.freeze
            end

            def append(batch_id:, entry:)
              current_entries(batch_id) << entry
              entry
            end

            def delete_by_batch(batch_id)
              entries = @by_batch_id.delete(batch_id)
              return EMPTY unless entries

              entries.dup.freeze
            end

            private

            def current_entries(batch_id)
              @by_batch_id[batch_id] ||= []
            end
          end

          private_constant :WorkflowHistory
        end
      end
    end
  end
end
