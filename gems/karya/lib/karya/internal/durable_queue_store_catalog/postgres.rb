# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStoreCatalog
      # Postgres durable schema definitions for the normalized queue-store model.
      module Postgres
        module_function

        def create_statements
          [
            metadata_sql,
            jobs_sql,
            queue_entries_sql,
            reservations_sql,
            workflow_batches_sql,
            workflow_steps_sql,
            workflow_interactions_sql,
            workflow_history_sql,
            uniqueness_keys_sql,
            idempotency_keys_sql,
            policy_state_sql,
            Shared.index_sql
          ].freeze
        end

        def schema_sql
          create_statements.join("\n\n")
        end

        def metadata_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:metadata)} (
              namespace text PRIMARY KEY,
              schema_version integer NOT NULL,
              reservation_token_sequence bigint NOT NULL DEFAULT 0,
              upgraded_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
              created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
              updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
          SQL
        end

        def jobs_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:jobs)} (
              namespace varchar(255) NOT NULL,
              job_id varchar(255) NOT NULL,
              queue varchar(255) NOT NULL,
              handler varchar(255) NOT NULL,
              arguments_payload text NOT NULL,
              priority integer NOT NULL,
              state varchar(64) NOT NULL,
              attempt integer NOT NULL DEFAULT 0,
              visible_at timestamptz,
              expires_at timestamptz,
              created_at timestamptz NOT NULL,
              enqueued_at timestamptz NOT NULL,
              updated_at timestamptz NOT NULL,
              retry_policy_payload text,
              execution_timeout_seconds integer,
              concurrency_scope varchar(255),
              rate_limit_scope varchar(255),
              idempotency_key varchar(255),
              uniqueness_key varchar(255),
              uniqueness_scope varchar(255),
              failure_classification varchar(64),
              dead_letter_reason varchar(255),
              dead_lettered_at timestamptz,
              dead_letter_source_state varchar(64),
              lifecycle_extensions_payload text,
              PRIMARY KEY (namespace, job_id)
            )
          SQL
        end

        def queue_entries_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:queue_entries)} (
              namespace varchar(255) NOT NULL,
              queue varchar(255) NOT NULL,
              job_id varchar(255) NOT NULL,
              state varchar(64) NOT NULL,
              visible_at timestamptz,
              priority integer NOT NULL,
              insertion_sequence bigint NOT NULL,
              handler varchar(255) NOT NULL,
              PRIMARY KEY (namespace, queue, job_id)
            )
          SQL
        end

        def reservations_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:reservations)} (
              namespace varchar(255) NOT NULL,
              reservation_token varchar(255) NOT NULL,
              job_id varchar(255) NOT NULL,
              worker_id varchar(255) NOT NULL,
              phase varchar(64) NOT NULL,
              reserved_at timestamptz NOT NULL,
              lease_expires_at timestamptz NOT NULL,
              PRIMARY KEY (namespace, reservation_token)
            )
          SQL
        end

        def workflow_batches_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:workflow_batches)} (
              namespace varchar(255) NOT NULL,
              batch_id varchar(255) NOT NULL,
              workflow_id varchar(255) NOT NULL,
              workflow_family varchar(255) NOT NULL,
              workflow_version varchar(255) NOT NULL,
              state varchar(64) NOT NULL,
              created_at timestamptz NOT NULL,
              updated_at timestamptz NOT NULL,
              PRIMARY KEY (namespace, batch_id)
            )
          SQL
        end

        def workflow_steps_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:workflow_steps)} (
              namespace varchar(255) NOT NULL,
              batch_id varchar(255) NOT NULL,
              step_id varchar(255) NOT NULL,
              step_sequence integer NOT NULL,
              job_id varchar(255),
              state varchar(64) NOT NULL,
              dependency_payload text,
              metadata_payload text,
              updated_at timestamptz NOT NULL,
              PRIMARY KEY (namespace, batch_id, step_id)
            )
          SQL
        end

        def workflow_interactions_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:workflow_interactions)} (
              namespace varchar(255) NOT NULL,
              batch_id varchar(255) NOT NULL,
              sequence bigint NOT NULL,
              kind varchar(64) NOT NULL,
              name varchar(255) NOT NULL,
              payload text NOT NULL,
              received_at timestamptz NOT NULL,
              PRIMARY KEY (namespace, batch_id, sequence)
            )
          SQL
        end

        def workflow_history_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:workflow_history)} (
              namespace varchar(255) NOT NULL,
              batch_id varchar(255) NOT NULL,
              sequence bigint NOT NULL,
              entry_type varchar(64) NOT NULL,
              details_payload text NOT NULL,
              occurred_at timestamptz NOT NULL,
              PRIMARY KEY (namespace, batch_id, sequence)
            )
          SQL
        end

        def uniqueness_keys_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:uniqueness_keys)} (
              namespace varchar(255) NOT NULL,
              uniqueness_scope varchar(255) NOT NULL,
              uniqueness_key varchar(255) NOT NULL,
              job_id varchar(255) NOT NULL,
              state varchar(64) NOT NULL,
              created_at timestamptz NOT NULL,
              updated_at timestamptz NOT NULL,
              PRIMARY KEY (namespace, uniqueness_scope, uniqueness_key)
            )
          SQL
        end

        def idempotency_keys_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:idempotency_keys)} (
              namespace varchar(255) NOT NULL,
              idempotency_key varchar(255) NOT NULL,
              job_id varchar(255) NOT NULL,
              state varchar(64) NOT NULL,
              created_at timestamptz NOT NULL,
              updated_at timestamptz NOT NULL,
              PRIMARY KEY (namespace, idempotency_key)
            )
          SQL
        end

        def policy_state_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:policy_state)} (
              namespace varchar(255) NOT NULL,
              policy_kind varchar(64) NOT NULL,
              scope_kind varchar(64) NOT NULL,
              scope_value varchar(255) NOT NULL,
              state_payload text NOT NULL,
              updated_at timestamptz NOT NULL,
              PRIMARY KEY (namespace, policy_kind, scope_kind, scope_value)
            )
          SQL
        end
      end
    end
  end
end
