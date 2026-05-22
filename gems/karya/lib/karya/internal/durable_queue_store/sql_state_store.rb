# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../durable_queue_store_catalog'

module Karya
  module Internal
    module DurableQueueStore
      # Shared SQL durable-row primitives for SQLite, Postgres, and MySQL.
      class SqlStateStore
        PRIMARY_KEYS = {
          metadata: %i[namespace],
          jobs: %i[namespace job_id],
          queue_entries: %i[namespace queue job_id],
          reservations: %i[namespace reservation_token],
          workflow_batches: %i[namespace batch_id],
          workflow_steps: %i[namespace batch_id step_id],
          workflow_interactions: %i[namespace batch_id sequence],
          workflow_history: %i[namespace batch_id sequence],
          uniqueness_keys: %i[namespace uniqueness_scope uniqueness_key],
          idempotency_keys: %i[namespace idempotency_key],
          policy_state: %i[namespace policy_kind scope_kind scope_value]
        }.freeze

        def initialize(table_names:)
          @table_names = table_names
        end

        def fetch_metadata(namespace:)
          row = select_one(
            "SELECT * FROM #{table_name(:metadata)} WHERE namespace = #{placeholder(1)}",
            [namespace]
          )
          return default_metadata unless row

          row
        end

        def fetch_rows_for_operation(operation_name:, namespace:, request:)
          case operation_name
          when :uniqueness_decision, :uniqueness_snapshot
            base_uniqueness_rows(namespace)
          when :enqueue
            enqueue_rows(namespace, request.fetch(:job))
          when :enqueue_many
            enqueue_many_rows(namespace, request.fetch(:jobs), request[:batch_id])
          when :reserve
            reserve_rows(namespace, request)
          when :release, :start_execution
            lease_rows(namespace, request.fetch(:reservation_token))
          when :complete_execution, :fail_execution, :reliability_snapshot
            full_lease_rows(namespace, request[:reservation_token])
          when :retry_jobs, :cancel_jobs, :dead_letter_jobs, :replay_dead_letter_jobs, :retry_dead_letter_jobs,
               :discard_dead_letter_jobs, :recover_in_flight, :expire_reservations, :expire_jobs, :backpressure_snapshot
            full_runtime_rows(namespace)
          when :recover_orphaned_jobs
            orphan_rows(namespace, request.fetch(:worker_id))
          when :batch_snapshot
            batch_snapshot_rows(namespace, request.fetch(:batch_id))
          when :pause_queue, :resume_queue
            pause_rows(namespace, request.fetch(:queue))
          when :enqueue_workflow, :workflow_snapshot, :workflow_history, :query_workflow,
               :deliver_workflow_signal, :deliver_workflow_event, :pause_workflow, :resume_workflow,
               :approve_workflow_checkpoints, :reject_workflow_checkpoints, :enqueue_child_workflow,
               :sync_child_workflows, :rollback_workflow, :retry_workflow_steps, :dead_letter_workflow_steps,
               :replay_workflow_steps, :retry_dead_letter_workflow_steps, :discard_workflow_steps
            workflow_runtime_rows(namespace)
          else
            raise NotImplementedError, "#{self.class} does not implement durable row reads for #{operation_name.inspect}"
          end
        end

        def lock_rows_for_operation(operation_name:, namespace:, request:, metadata:, rows:)
          _operation_name = operation_name
          _namespace = namespace
          _request = request
          _metadata = metadata
          _rows = rows
          nil
        end

        def apply_mutation_plan(plan:, namespace:)
          apply_metadata_updates(plan.metadata_updates, namespace)
          apply_group(plan.inserts) { |group_name, row| insert_row(group_name, row) }
          apply_group(plan.updates) { |group_name, row| update_row(group_name, row) }
          apply_group(plan.deletes) { |group_name, row| delete_row(group_name, row) }
          nil
        end

        private

        attr_reader :table_names

        def default_metadata
          {
            namespace: nil,
            schema_version: DurableQueueStoreCatalog.schema_version,
            reservation_token_sequence: 0
          }.freeze
        end

        def base_uniqueness_rows(namespace)
          {
            jobs: select_namespace_rows(:jobs, namespace),
            reservations: select_namespace_rows(:reservations, namespace),
            queue_entries: []
          }.freeze
        end

        def enqueue_rows(namespace, job)
          uniqueness_rows = base_uniqueness_rows(namespace)
          uniqueness_rows.merge(
            queue_entries: select_rows(:queue_entries, namespace:, queue: job.queue)
          ).freeze
        end

        def pause_rows(namespace, queue)
          {
            policy_state: select_rows(
              :policy_state,
              namespace:,
              policy_kind: 'paused_queue',
              scope_kind: 'queue',
              scope_value: queue
            )
          }.freeze
        end

        def full_runtime_rows(namespace)
          {
            jobs: select_namespace_rows(:jobs, namespace),
            queue_entries: select_namespace_rows(:queue_entries, namespace),
            reservations: select_namespace_rows(:reservations, namespace),
            policy_state: select_namespace_rows(:policy_state, namespace),
            workflow_batches: select_namespace_rows(:workflow_batches, namespace),
            workflow_steps: select_namespace_rows(:workflow_steps, namespace),
            workflow_interactions: select_namespace_rows(:workflow_interactions, namespace),
            workflow_history: select_namespace_rows(:workflow_history, namespace)
          }.freeze
        end

        def workflow_runtime_rows(namespace)
          full_runtime_rows(namespace)
        end

        def orphan_rows(namespace, worker_id)
          runtime_rows = full_runtime_rows(namespace)
          runtime_rows.merge(
            reservations: runtime_rows.fetch(:reservations).select { |row| row.fetch(:worker_id) == worker_id }.freeze
          ).freeze
        end

        def reserve_rows(namespace, request)
          runtime_rows = full_runtime_rows(namespace)
          requested_queues = Array(request[:queue] || request[:queues]).compact
          queue_entries = requested_queues.flat_map do |queue|
            select_rows(:queue_entries, namespace:, queue:)
          end
          reservations = runtime_rows.fetch(:reservations)
          runtime_rows.merge(
            jobs: runtime_rows.fetch(:jobs),
            queue_entries:,
            reservations:,
            policy_state: runtime_rows.fetch(:policy_state)
          ).freeze
        end

        def enqueue_many_rows(namespace, jobs, batch_id)
          queued_rows_by_queue = jobs.each_with_object({}) do |job, grouped|
            queue = job.queue
            queued_rows = grouped[queue] ||= []
            queued_rows.concat(select_rows(:queue_entries, namespace:, queue:)) if queued_rows.empty?
          end
          rows = base_uniqueness_rows(namespace).merge(
            queue_entries: queued_rows_by_queue.values.flatten
          )
          return rows.freeze unless batch_id

          normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)

          rows.merge(
            workflow_batches: select_rows(:workflow_batches, namespace:, batch_id: normalized_batch_id),
            workflow_steps: select_rows(:workflow_steps, namespace:, batch_id: normalized_batch_id)
          ).freeze
        end

        def batch_snapshot_rows(namespace, batch_id)
          normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)
          workflow_batches = select_rows(:workflow_batches, namespace:, batch_id: normalized_batch_id)
          workflow_steps = select_rows(:workflow_steps, namespace:, batch_id: normalized_batch_id)
          job_ids = workflow_steps.filter_map { |row| row[:job_id] }

          full_runtime_rows(namespace).merge(
            workflow_batches:,
            workflow_steps:,
            jobs: job_ids.map { |job_id| select_rows(:jobs, namespace:, job_id:) }.flatten
          ).freeze
        end

        def lease_rows(namespace, reservation_token)
          runtime_rows = full_runtime_rows(namespace)
          reservations = select_rows(:reservations, namespace:, reservation_token:)
          runtime_rows.merge(
            jobs: runtime_rows.fetch(:jobs),
            queue_entries: runtime_rows.fetch(:queue_entries),
            reservations:
          ).freeze
        end

        def full_lease_rows(namespace, reservation_token)
          rows = reservation_token ? lease_rows(namespace, reservation_token) : full_runtime_rows(namespace)
          rows.merge(policy_state: select_namespace_rows(:policy_state, namespace)).freeze
        end

        def select_namespace_rows(group_name, namespace)
          select_rows(group_name, namespace:)
        end

        def select_rows(group_name, **conditions)
          select_all(build_select_sql(group_name, conditions), conditions.values)
        end

        def select_one(sql, binds)
          select_all(sql, binds).first
        end

        def build_select_sql(group_name, conditions)
          where_clause = conditions.each_key.with_index(1).map do |column, index|
            "#{column} = #{placeholder(index)}"
          end.join(' AND ')
          "SELECT * FROM #{table_name(group_name)} WHERE #{where_clause}"
        end

        def apply_group(groups)
          groups.each do |group_name, rows|
            rows.each { |row| yield(group_name, row) }
          end
        end

        def apply_metadata_updates(metadata_updates, namespace)
          return if metadata_updates.empty?

          current_metadata = fetch_metadata(namespace:)
          current = current_metadata.merge(namespace:)
          row = current.merge(metadata_updates)
          primary_key_names = PRIMARY_KEYS.fetch(:metadata)
          if current_metadata[:namespace]
            update_by_keys(:metadata, row, primary_key_names)
          else
            insert_row(:metadata, row)
          end
        end

        def insert_row(group_name, row)
          columns = row.keys
          sql = "INSERT INTO #{table_name(group_name)} (#{columns.join(', ')}) VALUES (#{placeholders(columns.length)})"
          execute_write(sql, columns.map { |column| row.fetch(column) })
        end

        def update_row(group_name, row)
          update_by_keys(group_name, row, PRIMARY_KEYS.fetch(group_name))
        end

        def update_by_keys(group_name, row, primary_key_names)
          mutable_columns = row.keys - primary_key_names
          set_clause = mutable_columns.each_with_index.map do |column, index|
            "#{column} = #{placeholder(index + 1)}"
          end.join(', ')
          where_clause = primary_key_names.each_with_index.map do |column, index|
            "#{column} = #{placeholder(mutable_columns.length + index + 1)}"
          end.join(' AND ')
          sql = "UPDATE #{table_name(group_name)} SET #{set_clause} WHERE #{where_clause}"
          mutable_values = values_for_columns(row, mutable_columns)
          primary_key_values = values_for_columns(row, primary_key_names)
          binds = mutable_values + primary_key_values
          execute_write(sql, binds)
        end

        def delete_row(group_name, row)
          primary_key_names = PRIMARY_KEYS.fetch(group_name)
          where_clause = primary_key_names.each_with_index.map do |column, index|
            "#{column} = #{placeholder(index + 1)}"
          end.join(' AND ')
          sql = "DELETE FROM #{table_name(group_name)} WHERE #{where_clause}"
          execute_write(sql, primary_key_names.map { |column| row.fetch(column) })
        end

        def placeholders(count)
          (1..count).map { |index| placeholder(index) }.join(', ')
        end

        def table_name(group_name)
          table_names.fetch(group_name)
        end

        def job_ids_from_rows(rows)
          rows.map { |row| row.fetch(:job_id) }
        end

        def values_for_columns(row, columns)
          columns.map { |column| row.fetch(column) }
        end

        def select_all(_sql, _binds)
          raise NotImplementedError, "#{self.class} must implement #select_all"
        end

        def execute_write(_sql, _binds)
          raise NotImplementedError, "#{self.class} must implement #execute_write"
        end

        def placeholder(_index)
          raise NotImplementedError, "#{self.class} must implement #placeholder"
        end
      end
    end
  end
end
