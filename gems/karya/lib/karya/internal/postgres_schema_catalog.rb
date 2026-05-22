# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Shared Postgres persistence catalog for the durable queue-store snapshot.
    module PostgresSchemaCatalog
      module_function

      TABLE_NAME = 'karya_queue_store_states'

      def create_table_sql
        <<~SQL
          CREATE TABLE IF NOT EXISTS #{TABLE_NAME} (
            namespace text PRIMARY KEY,
            payload text NOT NULL,
            updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
          )
        SQL
      end

      def render_active_record_migration(class_name:, migration_version:)
        <<~RUBY
          # frozen_string_literal: true

          class #{class_name} < ActiveRecord::Migration[#{migration_version}]
            def change
              create_table :#{TABLE_NAME}, id: false do |t|
                t.text :namespace, null: false, primary_key: true
                t.text :payload, null: false
                t.datetime :updated_at, null: false, precision: 6
              end
            end
          end
        RUBY
      end

      def render_sequel_migration
        <<~RUBY
          # frozen_string_literal: true

          Sequel.migration do
            change do
              create_table?(:#{TABLE_NAME}) do
                String :namespace, null: false, primary_key: true
                String :payload, text: true, null: false
                DateTime :updated_at, null: false
              end
            end
          end
        RUBY
      end
    end
  end
end
