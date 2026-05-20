# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../../internal/mysql_schema_catalog'

module Karya
  module QueueStore
    class MySQL
      module Internal
        # MySQL-backed synchronization boundary for shared queue-store state.
        class PersistenceMutex
          def initialize(connection:, owner:)
            @connection = connection
            @owner = owner
            @local_mutex = Thread::Mutex.new
          end

          def ensure_schema
            connection.query(Karya::Internal::MySQLSchemaCatalog.create_table_sql)
            nil
          end

          def synchronize(persist_if: nil, &)
            synchronize_owned_state(persist_if:, &)
          end

          def read_only_synchronize(&)
            synchronize_owned_state(read_only: true, &)
          end

          def load_state_snapshot
            rows = connection.query(select_sql(lock: false), as: :hash, symbolize_keys: false).to_a
            return nil if rows.empty?

            StateCodec.load(rows[0].fetch('payload'))
          end

          private

          attr_reader :connection, :local_mutex, :owner

          def synchronize_owned_state(read_only: false, persist_if: nil)
            local_mutex.synchronize do
              with_transaction do
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

          def with_transaction
            connection.query('START TRANSACTION')
            lock_current_row
            result = yield
            connection.query('COMMIT')
            result
          rescue StandardError
            safe_rollback
            raise
          end

          def lock_current_row
            ensure_lockable_row
            connection.query(select_sql(lock: true), as: :hash, symbolize_keys: false)
            nil
          end

          def persist_snapshot_if_needed(result, persist_if)
            return if persist_if && !persist_if.call(result)

            connection.query(upsert_sql(owner.send(:dump_state_payload)))
            nil
          end

          def restore_owner_state_after_failure
            owner.send(:restore_authoritative_state_after_failure)
            nil
          rescue StandardError
            nil
          end

          def safe_rollback
            connection.query('ROLLBACK')
            nil
          rescue StandardError
            nil
          end

          def escaped_namespace
            connection.escape(owner.namespace)
          end

          def select_sql(lock:)
            sql = <<~SQL
              SELECT payload
              FROM #{Karya::Internal::MySQLSchemaCatalog::TABLE_NAME}
              WHERE namespace = '#{escaped_namespace}'
            SQL
            lock ? "#{sql.rstrip} FOR UPDATE" : sql
          end

          def ensure_lockable_row
            connection.query(insert_placeholder_sql)
            nil
          end

          def insert_placeholder_sql
            escaped_payload = connection.escape(initial_payload)
            <<~SQL
              INSERT IGNORE INTO #{Karya::Internal::MySQLSchemaCatalog::TABLE_NAME} (namespace, payload, updated_at)
              VALUES ('#{escaped_namespace}', '#{escaped_payload}', CURRENT_TIMESTAMP(6))
            SQL
          end

          def initial_payload
            StateCodec.dump(
              state: StoreState.new(expired_tombstone_limit: owner.send(:expired_tombstone_limit)),
              reservation_token_sequence: 0
            )
          end

          def upsert_sql(payload)
            escaped_payload = connection.escape(payload)
            <<~SQL
              INSERT INTO #{Karya::Internal::MySQLSchemaCatalog::TABLE_NAME} (namespace, payload, updated_at)
              VALUES ('#{escaped_namespace}', '#{escaped_payload}', CURRENT_TIMESTAMP(6))
              ON DUPLICATE KEY UPDATE payload = VALUES(payload), updated_at = VALUES(updated_at)
            SQL
          end
        end
      end
    end
  end
end
