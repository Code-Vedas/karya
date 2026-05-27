# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'durable_queue_store_catalog/shared'
require_relative 'durable_queue_store_catalog/postgres'
require_relative 'durable_queue_store_catalog/mysql'
require_relative 'durable_queue_store_catalog/sqlite'

module Karya
  module Internal
    # Shared normalized durable-schema catalog for the next queue-store model.
    module DurableQueueStoreCatalog
      module_function

      SCHEMA_VERSION = 2

      def schema_version = SCHEMA_VERSION

      def table_name(name)
        Shared.table_name(name)
      end

      def table_names
        Shared.table_names
      end

      def postgres_create_statements
        Postgres.create_statements
      end

      def mysql_create_statements
        MySQL.create_statements
      end

      def sqlite_create_statements
        SQLite.create_statements
      end

      def postgres_schema_sql
        Postgres.schema_sql
      end

      def mysql_schema_sql
        MySQL.schema_sql
      end

      def sqlite_schema_sql
        SQLite.schema_sql
      end
    end
  end
end
