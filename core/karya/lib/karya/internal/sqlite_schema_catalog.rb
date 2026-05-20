# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Shared SQLite persistence catalog for the durable queue-store snapshot.
    module SQLiteSchemaCatalog
      module_function

      TABLE_NAME = 'karya_queue_store_states'

      def create_table_sql
        <<~SQL
          CREATE TABLE IF NOT EXISTS #{TABLE_NAME} (
            namespace text PRIMARY KEY,
            payload text NOT NULL,
            updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP
          )
        SQL
      end

      def drop_table_sql
        "DROP TABLE IF EXISTS #{TABLE_NAME}"
      end

      def render_active_record_migration(class_name:, migration_version:)
        <<~RUBY
          # frozen_string_literal: true

          class #{class_name} < ActiveRecord::Migration[#{migration_version}]
            def up
              execute <<~SQL
                #{create_table_sql.rstrip}
              SQL
            end

            def down
              execute <<~SQL
                #{drop_table_sql}
              SQL
            end
          end
        RUBY
      end

      def render_sequel_migration
        <<~RUBY
          # frozen_string_literal: true

          Sequel.migration do
            up do
              run <<~SQL
                #{create_table_sql.rstrip}
              SQL
            end

            down do
              run <<~SQL
                #{drop_table_sql}
              SQL
            end
          end
        RUBY
      end
    end
  end
end
