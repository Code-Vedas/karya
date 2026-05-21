# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../../internal/sqlite_schema_catalog'

module Karya
  module QueueStore
    class SQLite
      module Internal
        # SQLite-backed synchronization boundary for shared queue-store state.
        class PersistenceMutex
          SELECT_SQL = <<~SQL.freeze
            SELECT payload
            FROM #{Karya::Internal::SQLiteSchemaCatalog::TABLE_NAME}
            WHERE namespace = ?
          SQL
          UPSERT_SQL = <<~SQL.freeze
            INSERT INTO #{Karya::Internal::SQLiteSchemaCatalog::TABLE_NAME} (namespace, payload, updated_at)
            VALUES (?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(namespace)
            DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at
          SQL

          def initialize(connection:, owner:)
            @fallback_connection = connection
            @owner = owner
            @local_mutex = Thread::Mutex.new
          end

          def ensure_schema
            connection.execute_batch(Karya::Internal::SQLiteSchemaCatalog.create_table_sql)
            nil
          end

          def synchronize(persist_if: nil, &)
            synchronize_owned_state(persist_if:, &)
          end

          def read_only_synchronize(&)
            synchronize_owned_state(read_only: true, &)
          end

          def load_state_snapshot
            rows = connection.execute(SELECT_SQL, [owner.namespace])
            return nil if rows.empty?

            StateCodec.load(rows[0].fetch('payload'))
          end

          private

          attr_reader :fallback_connection, :local_mutex, :owner

          def synchronize_owned_state(read_only: false, persist_if: nil)
            local_mutex.synchronize do
              with_transaction(read_only:) do
                owner.send(:restore_state_snapshot, load_state_snapshot)
                result = yield
                persist_snapshot_if_needed(result, persist_if) unless read_only
                result
              end
            rescue StandardError
              restore_owner_state_after_failure
              raise
            end
          end

          def with_transaction(read_only: false)
            connection.execute(read_only ? 'BEGIN TRANSACTION' : 'BEGIN IMMEDIATE TRANSACTION')
            result = yield
            connection.execute('COMMIT')
            result
          rescue StandardError
            safe_rollback
            raise
          end

          def persist_snapshot_if_needed(result, persist_if)
            return if persist_if && !persist_if.call(result)

            connection.execute(UPSERT_SQL, [owner.namespace, owner.send(:dump_state_payload)])
            nil
          end

          def restore_owner_state_after_failure
            owner.send(:restore_authoritative_state_after_failure)
            nil
          rescue StandardError
            nil
          end

          def safe_rollback
            connection.execute('ROLLBACK')
            nil
          rescue StandardError
            nil
          end

          def connection
            owner.send(:connection)
          rescue NoMethodError
            fallback_connection
          end
        end
      end
    end
  end
end
