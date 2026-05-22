# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class SQLite
      module Internal
        # Builds SQLite durable-store reserve queries.
        # :nocov:
        module QueryBuilder
          module_function

          def reserve_candidate_query(queue_entries_table:, handler_names:)
            if handler_names
              placeholders = Array.new(handler_names.length, '?').join(', ')
              [
                <<~SQL,
                  SELECT job_id
                  FROM #{queue_entries_table}
                  WHERE namespace = ?
                    AND queue = ?
                    AND state = 'queued'
                    AND visible_at <= ?
                    AND handler IN (#{placeholders})
                  ORDER BY priority DESC, insertion_sequence ASC
                SQL
                handler_names
              ]
            else
              [
                <<~SQL,
                  SELECT job_id
                  FROM #{queue_entries_table}
                  WHERE namespace = ?
                    AND queue = ?
                    AND state = 'queued'
                    AND visible_at <= ?
                  ORDER BY priority DESC, insertion_sequence ASC
                SQL
                nil
              ]
            end
          end

          def queue_entry_query(queue_entries_table:, queue_entries_order:, namespace:, queues:, state_name:)
            if queues
              placeholders = Array.new(queues.length, '?').join(', ')
              [
                <<~SQL,
                  SELECT *
                  FROM #{queue_entries_table}
                  WHERE namespace = ?
                    AND queue IN (#{placeholders})
                    AND state = '#{state_name}'
                  #{queue_entries_order}
                SQL
                [namespace, *queues]
              ]
            else
              [
                <<~SQL,
                  SELECT *
                  FROM #{queue_entries_table}
                  WHERE namespace = ?
                    AND state = '#{state_name}'
                  #{queue_entries_order}
                SQL
                [namespace]
              ]
            end
          end
        end
        # :nocov:
      end
    end
  end
end
