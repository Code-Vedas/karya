# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Keeps workflow rows in sync with job state transitions.
        class WorkflowRowMutator
          def initialize(host:, store:, rows:)
            @host = host
            @store = store
            @rows = rows
          end

          def batch_row(batch_id)
            rows.fetch(:workflow_batches).find { |row| row.fetch(:batch_id) == batch_id }
          end

          def batch_from_rows(batch_id)
            current_batch_row = batch_row(batch_id)
            raise Workflow::UnknownBatchError, "batch #{batch_id.inspect} is not registered" unless current_batch_row

            Workflow::Batch.new(
              id: batch_id,
              job_ids: step_rows_for_batch(batch_id).map { |row| row.fetch(:job_id) },
              created_at: current_batch_row.fetch(:created_at),
              updated_at: current_batch_row.fetch(:updated_at),
              max_size: store.send(:max_batch_size)
            )
          end

          def step_rows_for_batch(batch_id)
            rows.fetch(:workflow_steps)
                .select { |row| workflow_step_row_for_batch?(row, batch_id) }
                .sort_by { |row| workflow_step_sequence(row) }
          end

          def step_rows_for_job(job_id)
            rows.fetch(:workflow_steps, []).select { |row| row.fetch(:job_id) == job_id }
          end

          def row_updates_for_job(context:, replacement_job:)
            replacement_job_id = replacement_job.id
            related_step_rows = step_rows_for_job(replacement_job_id)
            return { workflow_steps: [], workflow_batches: [] }.freeze if related_step_rows.empty?

            updated_rows = update_rows_with_job(replacement_job_id, replacement_job)
            {
              workflow_steps: updated_step_rows(related_step_rows, replacement_job),
              workflow_batches: rebuild_batch_rows(context.namespace, updated_rows, related_step_rows)
            }.freeze
          end

          def update_rows_with_job(job_id, replacement_job)
            rows.merge(
              jobs: rows.fetch(:jobs).map do |row|
                row.fetch(:job_id) == job_id ? JobRecord.new(namespace: rows.fetch(:namespace), job: replacement_job).to_h : row
              end
            )
          end

          def history_rows_for_job(namespace:, replacement_job:, from_state: nil)
            replacement_job_id = replacement_job.id
            previous_state = previous_state_for(replacement_job_id, from_state)
            return [].freeze unless previous_state

            step_rows_for_job(replacement_job_id).map do |step_row|
              build_step_history_row(step_row:, namespace:, replacement_job:, previous_state:)
            end.freeze
          end

          private

          attr_reader :host, :store, :rows

          def updated_step_rows(step_rows, replacement_job)
            step_rows.map do |row|
              row.merge(state: replacement_job.state.to_s, updated_at: replacement_job.updated_at)
            end
          end

          def rebuild_batch_rows(namespace, updated_rows, step_rows)
            step_rows.map { |row| row.fetch(:batch_id) }.uniq.map do |batch_id|
              rebuild_batch_row(namespace, updated_rows, batch_id)
            end
          end

          def previous_state_for(job_id, from_state)
            return from_state if from_state

            Operations::RowIndex.new(rows:).jobs_by_id[job_id]&.fetch(:state)&.to_sym
          end

          def build_step_history_row(step_row:, namespace:, replacement_job:, previous_state:)
            step_batch_id = step_row.fetch(:batch_id)
            registration = host.send(:registration_for_batch, rows, step_batch_id)
            entry = Workflow::HistoryEntry.new(
              kind: :step,
              action: replacement_job.state,
              occurred_at: replacement_job.updated_at,
              workflow_id: registration.workflow_id,
              workflow_family: registration.workflow_family,
              workflow_version: registration.workflow_version,
              batch_id: step_batch_id,
              step_id: step_row.fetch(:step_id),
              job_id: replacement_job.id,
              details: { 'from_state' => previous_state.to_s }
            )
            host.send(:build_workflow_history_row, rows:, namespace:, batch_id: step_batch_id, entry:)
          end

          def rebuild_batch_row(namespace, updated_rows, batch_id)
            registration = host.send(:registration_for_batch, updated_rows, batch_id)
            batch = self.class.new(host:, store:, rows: updated_rows).batch_from_rows(batch_id)
            row_index = Operations::RowIndex.new(rows: updated_rows)
            jobs_for_batch = batch.job_ids.to_h do |job_id|
              [job_id, Operations::JobRow.new(row: row_index.jobs_by_id.fetch(job_id)).to_job]
            end
            WorkflowBatchRecord.new(namespace:, batch:, registration:, jobs_by_id: jobs_for_batch).to_h
          end

          def workflow_step_row_for_batch?(row, batch_id)
            row.fetch(:batch_id) == batch_id
          end

          def workflow_step_sequence(row)
            row.fetch(:step_sequence)
          end
        end
      end
    end
  end
end
