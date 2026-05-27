# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'time'

module Karya
  module QueueStore
    class SQLite
      module Internal
        # SQLite-backed row reader/writer for the durable queue-store schema.
        class DurableStateStore < Karya::Internal::DurableQueueStore::SqlStateStore
          TIME_COLUMNS = %i[
            created_at
            enqueued_at
            updated_at
            visible_at
            expires_at
            dead_lettered_at
            decided_at
            occurred_at
            received_at
            requested_at
            reserved_at
            lease_expires_at
            upgraded_at
          ].freeze

          def initialize(connection:)
            super(table_names: Karya::Internal::DurableQueueStoreCatalog.table_names)
            @connection = connection
          end

          private

          attr_reader :connection

          def select_all(sql, binds)
            connection.execute(sql, normalize_binds(binds)).map do |row|
              normalize_row(row)
            end
          end

          def execute_write(sql, binds)
            connection.execute(sql, normalize_binds(binds))
          end

          def placeholder(_index)
            '?'
          end

          def normalize_row(row)
            row.each_with_object({}) do |(key, value), normalized|
              column_name = key.to_sym
              normalized[column_name] = normalize_value(column_name, value)
            end
          end

          def normalize_value(column_name, value)
            return value unless TIME_COLUMNS.include?(column_name) && value.is_a?(String)

            Time.parse(value).utc
          end

          def normalize_binds(binds)
            binds.map do |value|
              value.is_a?(Time) ? value.utc.iso8601(6) : value
            end
          end
        end
      end
    end
  end
end
