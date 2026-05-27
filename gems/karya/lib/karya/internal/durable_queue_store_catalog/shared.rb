# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStoreCatalog
      # Shared durable table names and common index statements.
      module Shared
        module_function

        TABLE_NAMES = {
          metadata: 'karya_queue_store_metadata',
          jobs: 'karya_queue_store_jobs',
          queue_entries: 'karya_queue_store_queue_entries',
          reservations: 'karya_queue_store_reservations',
          workflow_batches: 'karya_queue_store_workflow_batches',
          workflow_steps: 'karya_queue_store_workflow_steps',
          workflow_interactions: 'karya_queue_store_workflow_interactions',
          workflow_history: 'karya_queue_store_workflow_history',
          uniqueness_keys: 'karya_queue_store_uniqueness_keys',
          idempotency_keys: 'karya_queue_store_idempotency_keys',
          policy_state: 'karya_queue_store_policy_state'
        }.freeze

        def table_name(name)
          TABLE_NAMES.fetch(name)
        end

        def table_names
          TABLE_NAMES.dup.freeze
        end

        def index_sql
          <<~SQL
            CREATE INDEX IF NOT EXISTS karya_queue_store_queue_entries_lookup
              ON #{table_name(:queue_entries)} (namespace, queue, state, priority DESC, insertion_sequence ASC);

            CREATE INDEX IF NOT EXISTS karya_queue_store_jobs_state_lookup
              ON #{table_name(:jobs)} (namespace, state, queue, priority DESC, visible_at ASC);

            CREATE INDEX IF NOT EXISTS karya_queue_store_reservations_job_lookup
              ON #{table_name(:reservations)} (namespace, job_id, phase);

            CREATE INDEX IF NOT EXISTS karya_queue_store_workflow_steps_job_lookup
              ON #{table_name(:workflow_steps)} (namespace, job_id);

            CREATE INDEX IF NOT EXISTS karya_queue_store_policy_state_lookup
              ON #{table_name(:policy_state)} (namespace, policy_kind, scope_kind, scope_value);
          SQL
        end
      end
    end
  end
end
