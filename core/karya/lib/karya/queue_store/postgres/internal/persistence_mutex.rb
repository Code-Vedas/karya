# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../../internal/postgres_schema_catalog'

module Karya
  module QueueStore
    class Postgres
      module Internal
        # Postgres-backed synchronization boundary for shared queue-store state.
        class PersistenceMutex
          SELECT_SQL = <<~SQL.freeze
            SELECT payload
            FROM #{Karya::Internal::PostgresSchemaCatalog::TABLE_NAME}
            WHERE namespace = $1
            FOR UPDATE
          SQL
          UPSERT_SQL = <<~SQL.freeze
            INSERT INTO #{Karya::Internal::PostgresSchemaCatalog::TABLE_NAME} (namespace, payload, updated_at)
            VALUES ($1, $2, CURRENT_TIMESTAMP)
            ON CONFLICT (namespace)
            DO UPDATE SET payload = EXCLUDED.payload, updated_at = EXCLUDED.updated_at
          SQL

          def initialize(connection:, owner:)
            @connection = connection
            @owner = owner
            @local_mutex = Thread::Mutex.new
          end

          def ensure_schema
            connection.exec(Karya::Internal::PostgresSchemaCatalog.create_table_sql)
            nil
          end

          def synchronize(persist_if: nil, &)
            synchronize_owned_state(persist_if:, &)
          end

          def read_only_synchronize(&)
            synchronize_owned_state(read_only: true, &)
          end

          def load_state_snapshot
            result = connection.exec_params(SELECT_SQL.sub(/\s+FOR UPDATE\s*\z/, ''), [owner.namespace])
            return nil if result.ntuples.zero?

            StateCodec.load(result[0].fetch('payload'))
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
            connection.exec('BEGIN')
            lock_current_row
            result = yield
            connection.exec('COMMIT')
            result
          rescue StandardError
            safe_rollback
            raise
          end

          def lock_current_row
            connection.exec_params(SELECT_SQL, [owner.namespace])
            nil
          end

          def persist_snapshot_if_needed(result, persist_if)
            return if persist_if && !persist_if.call(result)

            connection.exec_params(UPSERT_SQL, [owner.namespace, owner.send(:dump_state_payload)])
            nil
          end

          def restore_owner_state_after_failure
            owner.send(:restore_authoritative_state_after_failure)
            nil
          rescue StandardError
            nil
          end

          def safe_rollback
            connection.exec('ROLLBACK')
            nil
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
