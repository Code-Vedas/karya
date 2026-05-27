# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../../internal/durable_queue_store_catalog'

module Karya
  module QueueStore
    class Postgres
      module Internal
        # Wraps durable Postgres operations in the backend transaction boundary.
        class PersistenceMutex
          def initialize(connection:, owner:)
            @connection = connection
            @owner = owner
            @durable_state_store = DurableStateStore.new(connection:)
          end

          def ensure_schema
            Karya::Internal::DurableQueueStoreCatalog.postgres_create_statements.each do |statement|
              connection.exec(statement)
            end
            nil
          end

          def run_mutation(operation_name: nil, &)
            _operation_name = operation_name
            run_transaction(&)
          end

          def run_reserve(operation_name: nil, &)
            _operation_name = operation_name
            run_transaction(&)
          end

          def run_read_only(operation_name: nil)
            _operation_name = operation_name
            yield
          end

          private

          attr_reader :connection, :durable_state_store, :owner

          def run_transaction
            connection.exec('BEGIN')
            result = yield
            connection.exec('COMMIT')
            result
          rescue StandardError
            connection.exec('ROLLBACK')
            raise
          end
        end
      end
    end
  end
end
