# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'base64'

module Karya
  module QueueStore
    class Redis
      module Internal
        # Redis-backed row-family store for the durable queue-store schema.
        class DurableStateStore
          PRIMARY_KEYS = {
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

          def initialize(redis:, namespace:)
            @redis = redis
            @namespace = namespace
          end

          def fetch_metadata(namespace:)
            payload = redis.hgetall(metadata_key(namespace))
            return default_metadata if payload.empty?

            {
              namespace: payload['namespace'],
              schema_version: payload.fetch('schema_version').to_i,
              reservation_token_sequence: payload.fetch('reservation_token_sequence', '0').to_i
            }.freeze
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
            apply_group(plan.inserts) { |group_name, row| write_row(group_name, row) }
            apply_group(plan.updates) { |group_name, row| write_row(group_name, row) }
            apply_group(plan.deletes) { |group_name, row| delete_row(group_name, row) }
            nil
          end

          private

          attr_reader :namespace, :redis

          def default_metadata
            {
              namespace: nil,
              schema_version: Karya::Internal::DurableQueueStoreCatalog.schema_version,
              reservation_token_sequence: 0
            }.freeze
          end

          def base_uniqueness_rows(current_namespace)
            {
              jobs: load_group(:jobs, current_namespace),
              reservations: load_group(:reservations, current_namespace),
              queue_entries: []
            }.freeze
          end

          def enqueue_rows(current_namespace, job)
            rows = base_uniqueness_rows(current_namespace)
            rows.merge(queue_entries: select_rows(:queue_entries, namespace: current_namespace, queue: job.queue)).freeze
          end

          def enqueue_many_rows(current_namespace, jobs, batch_id)
            queue_entries = jobs.flat_map do |job|
              select_rows(:queue_entries, namespace: current_namespace, queue: job.queue)
            end
            rows = base_uniqueness_rows(current_namespace).merge(queue_entries: queue_entries)
            return rows.freeze unless batch_id

            normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)
            rows.merge(
              workflow_batches: select_rows(:workflow_batches, namespace: current_namespace, batch_id: normalized_batch_id),
              workflow_steps: select_rows(:workflow_steps, namespace: current_namespace, batch_id: normalized_batch_id)
            ).freeze
          end

          def reserve_rows(current_namespace, request)
            runtime_rows = full_runtime_rows(current_namespace)
            requested_queues = Array(request[:queue] || request[:queues]).compact
            queue_entries = requested_queues.flat_map do |queue|
              select_rows(:queue_entries, namespace: current_namespace, queue:)
            end
            reservations = runtime_rows.fetch(:reservations)
            runtime_rows.merge(
              jobs: runtime_rows.fetch(:jobs),
              queue_entries:,
              reservations:,
              policy_state: runtime_rows.fetch(:policy_state)
            ).freeze
          end

          def lease_rows(current_namespace, reservation_token)
            runtime_rows = full_runtime_rows(current_namespace)
            reservations = select_rows(:reservations, namespace: current_namespace, reservation_token:)
            runtime_rows.merge(
              jobs: runtime_rows.fetch(:jobs),
              queue_entries: runtime_rows.fetch(:queue_entries),
              reservations:
            ).freeze
          end

          def full_lease_rows(current_namespace, reservation_token)
            rows = reservation_token ? lease_rows(current_namespace, reservation_token) : full_runtime_rows(current_namespace)
            rows.merge(policy_state: load_group(:policy_state, current_namespace)).freeze
          end

          def full_runtime_rows(current_namespace)
            {
              jobs: load_group(:jobs, current_namespace),
              queue_entries: load_group(:queue_entries, current_namespace),
              reservations: load_group(:reservations, current_namespace),
              policy_state: load_group(:policy_state, current_namespace),
              workflow_batches: load_group(:workflow_batches, current_namespace),
              workflow_steps: load_group(:workflow_steps, current_namespace),
              workflow_interactions: load_group(:workflow_interactions, current_namespace),
              workflow_history: load_group(:workflow_history, current_namespace)
            }.freeze
          end

          def workflow_runtime_rows(current_namespace)
            full_runtime_rows(current_namespace)
          end

          def orphan_rows(current_namespace, worker_id)
            rows = full_runtime_rows(current_namespace)
            rows.merge(
              reservations: rows.fetch(:reservations).select { |row| row.fetch(:worker_id) == worker_id }.freeze
            ).freeze
          end

          def batch_snapshot_rows(current_namespace, batch_id)
            normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)
            workflow_batches = select_rows(:workflow_batches, namespace: current_namespace, batch_id: normalized_batch_id)
            workflow_steps = select_rows(:workflow_steps, namespace: current_namespace, batch_id: normalized_batch_id)
            job_ids = workflow_steps.filter_map { |row| row[:job_id] }
            full_runtime_rows(current_namespace).merge(
              workflow_batches:,
              workflow_steps:,
              jobs: job_ids.flat_map { |job_id| select_rows(:jobs, namespace: current_namespace, job_id:) }
            ).freeze
          end

          def pause_rows(current_namespace, queue)
            {
              policy_state: select_rows(
                :policy_state,
                namespace: current_namespace,
                policy_kind: 'paused_queue',
                scope_kind: 'queue',
                scope_value: queue
              )
            }.freeze
          end

          def apply_metadata_updates(metadata_updates, current_namespace)
            return if metadata_updates.empty?

            metadata = fetch_metadata(namespace: current_namespace).merge(namespace: current_namespace)
            row = metadata.merge(metadata_updates)
            redis.hset(
              metadata_key(current_namespace),
              'namespace', row.fetch(:namespace),
              'schema_version', row.fetch(:schema_version),
              'reservation_token_sequence', row.fetch(:reservation_token_sequence)
            )
          end

          def write_row(group_name, row)
            redis.hset(group_key(group_name, row.fetch(:namespace)), group_field(group_name, row), dump_row(row))
          end

          def delete_row(group_name, row)
            redis.hdel(group_key(group_name, row.fetch(:namespace)), group_field(group_name, row))
          end

          def load_group(group_name, current_namespace)
            redis.hvals(group_key(group_name, current_namespace)).map { |payload| load_row(payload) }.freeze
          end

          def select_rows(group_name, **conditions)
            load_group(group_name, conditions.fetch(:namespace)).select do |row|
              conditions.all? { |column, value| row.fetch(column) == value }
            end.freeze
          end

          def group_key(group_name, current_namespace)
            "#{current_namespace}:queue_store:rows:#{group_name}"
          end

          def metadata_key(current_namespace)
            "#{current_namespace}:queue_store:metadata"
          end

          def group_field(group_name, row)
            PRIMARY_KEYS.fetch(group_name).map { |column| row.fetch(column).to_s }.join('|')
          end

          def dump_row(row)
            Base64.strict_encode64(Karya::Internal::DurableQueueStore::PayloadCodec.dump(stringify_row_keys(row)))
          end

          def load_row(payload)
            symbolize_row_keys(Karya::Internal::DurableQueueStore::PayloadCodec.decode(Base64.strict_decode64(payload)))
          end

          def stringify_row_keys(row)
            row.to_h { |key, value| [key.to_s, value] }
          end

          def symbolize_row_keys(row)
            row.to_h { |key, value| [key.to_sym, value] }
          end

          def apply_group(groups)
            groups.each do |group_name, rows|
              rows.each { |row| yield(group_name, row) }
            end
          end
        end
      end
    end
  end
end
