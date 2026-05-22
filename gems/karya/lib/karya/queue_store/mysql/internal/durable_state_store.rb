# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'time'

module Karya
  module QueueStore
    class MySQL
      module Internal
        # MySQL-backed row reader/writer for the durable queue-store schema.
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
          INTEGER_COLUMNS = %i[
            priority
            attempt
            insertion_sequence
            reservation_token_sequence
            execution_timeout_seconds
            schema_version
            step_sequence
            sequence
          ].freeze

          def initialize(connection:)
            super(table_names: Karya::Internal::DurableQueueStoreCatalog.table_names)
            @connection = connection
          end

          private

          attr_reader :connection

          def select_all(sql, binds)
            statement = connection.prepare(sql)
            statement.execute(*binds).map do |row|
              row.each_with_object({}) do |(key, value), normalized|
                column_name = key.to_sym
                normalized[column_name] = normalize_value(column_name, value)
              end
            end
          end

          def execute_write(sql, binds)
            connection.prepare(sql).execute(*binds)
          end

          def placeholder(_index)
            '?'
          end

          def normalize_value(column_name, value)
            return value if value.nil?
            return utc_wall_clock_time(value) if TIME_COLUMNS.include?(column_name) && value.is_a?(Time)
            return Time.parse(value).utc if TIME_COLUMNS.include?(column_name) && value.is_a?(String)
            return value.to_i if INTEGER_COLUMNS.include?(column_name) && value.is_a?(String)

            value
          end

          def utc_wall_clock_time(value)
            Time.utc(
              value.year,
              value.month,
              value.day,
              value.hour,
              value.min,
              value.sec + value.subsec
            )
          end
        end
      end
    end
  end
end
