# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStoreCatalog
      # MySQL durable schema definitions for the normalized queue-store model.
      module MySQL
        module_function

        TABLE_SUFFIX = ' CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci'
        private_constant :TABLE_SUFFIX

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
            *index_statements
          ].freeze
        end

        def schema_sql
          create_statements.join("\n\n")
        end

        def metadata_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:metadata)} (
              namespace varchar(255) PRIMARY KEY,
              schema_version integer NOT NULL,
              reservation_token_sequence bigint NOT NULL DEFAULT 0,
              upgraded_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
              created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
              updated_at datetime(6) NOT NULL
                DEFAULT CURRENT_TIMESTAMP(6)
                ON UPDATE CURRENT_TIMESTAMP(6)
            )#{TABLE_SUFFIX}
          SQL
        end

        def jobs_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:jobs)} (
              namespace varchar(255) NOT NULL,
              job_id varchar(255) NOT NULL,
              queue varchar(255) NOT NULL,
              handler varchar(255) NOT NULL,
              arguments_payload longtext NOT NULL,
              priority integer NOT NULL,
              state varchar(64) NOT NULL,
              attempt integer NOT NULL DEFAULT 0,
              visible_at datetime(6),
              expires_at datetime(6),
              created_at datetime(6) NOT NULL,
              enqueued_at datetime(6) NOT NULL,
              updated_at datetime(6) NOT NULL,
              retry_policy_payload longtext,
              execution_timeout_seconds integer,
              concurrency_scope varchar(255),
              rate_limit_scope varchar(255),
              idempotency_key varchar(255),
              uniqueness_key varchar(255),
              uniqueness_scope varchar(255),
              failure_classification varchar(64),
              dead_letter_reason varchar(255),
              dead_lettered_at datetime(6),
              dead_letter_source_state varchar(64),
              lifecycle_extensions_payload longtext,
              PRIMARY KEY (namespace, job_id)
            )#{TABLE_SUFFIX}
          SQL
        end

        def queue_entries_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:queue_entries)} (
              namespace varchar(255) NOT NULL,
              queue varchar(255) NOT NULL,
              job_id varchar(255) NOT NULL,
              state varchar(64) NOT NULL,
              visible_at datetime(6),
              priority integer NOT NULL,
              insertion_sequence bigint NOT NULL,
              handler varchar(255) NOT NULL,
              PRIMARY KEY (namespace, queue, job_id)
            )#{TABLE_SUFFIX}
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
              reserved_at datetime(6) NOT NULL,
              lease_expires_at datetime(6) NOT NULL,
              PRIMARY KEY (namespace, reservation_token)
            )#{TABLE_SUFFIX}
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
              created_at datetime(6) NOT NULL,
              updated_at datetime(6) NOT NULL,
              PRIMARY KEY (namespace, batch_id)
            )#{TABLE_SUFFIX}
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
              dependency_payload longtext,
              metadata_payload longtext,
              updated_at datetime(6) NOT NULL,
              PRIMARY KEY (namespace, batch_id, step_id)
            )#{TABLE_SUFFIX}
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
              payload longtext NOT NULL,
              received_at datetime(6) NOT NULL,
              PRIMARY KEY (namespace, batch_id, sequence)
            )#{TABLE_SUFFIX}
          SQL
        end

        def workflow_history_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:workflow_history)} (
              namespace varchar(255) NOT NULL,
              batch_id varchar(255) NOT NULL,
              sequence bigint NOT NULL,
              entry_type varchar(64) NOT NULL,
              details_payload longtext NOT NULL,
              occurred_at datetime(6) NOT NULL,
              PRIMARY KEY (namespace, batch_id, sequence)
            )#{TABLE_SUFFIX}
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
              created_at datetime(6) NOT NULL,
              updated_at datetime(6) NOT NULL,
              PRIMARY KEY (namespace, uniqueness_scope, uniqueness_key)
            )#{TABLE_SUFFIX}
          SQL
        end

        def idempotency_keys_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:idempotency_keys)} (
              namespace varchar(255) NOT NULL,
              idempotency_key varchar(255) NOT NULL,
              job_id varchar(255) NOT NULL,
              state varchar(64) NOT NULL,
              created_at datetime(6) NOT NULL,
              updated_at datetime(6) NOT NULL,
              PRIMARY KEY (namespace, idempotency_key)
            )#{TABLE_SUFFIX}
          SQL
        end

        def policy_state_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS #{Shared.table_name(:policy_state)} (
              namespace varchar(255) NOT NULL,
              policy_kind varchar(64) NOT NULL,
              scope_kind varchar(64) NOT NULL,
              scope_value varchar(255) NOT NULL,
              state_payload longtext NOT NULL,
              updated_at datetime(6) NOT NULL,
              PRIMARY KEY (namespace, policy_kind, scope_kind, scope_value)
            )#{TABLE_SUFFIX}
          SQL
        end

        def index_statements
          [
            "CREATE INDEX karya_queue_store_queue_entries_lookup ON #{Shared.table_name(:queue_entries)} " \
            '(namespace, queue, state, priority DESC, insertion_sequence ASC)',
            "CREATE INDEX karya_queue_store_jobs_state_lookup ON #{Shared.table_name(:jobs)} " \
            '(namespace, state, queue, priority DESC, visible_at ASC)',
            "CREATE INDEX karya_queue_store_reservations_job_lookup ON #{Shared.table_name(:reservations)} " \
            '(namespace, job_id, phase)',
            "CREATE INDEX karya_queue_store_workflow_steps_job_lookup ON #{Shared.table_name(:workflow_steps)} " \
            '(namespace, job_id)',
            "CREATE INDEX karya_queue_store_policy_state_lookup ON #{Shared.table_name(:policy_state)} " \
            '(namespace, policy_kind, scope_kind, scope_value)'
          ].freeze
        end
      end
    end
  end
end
