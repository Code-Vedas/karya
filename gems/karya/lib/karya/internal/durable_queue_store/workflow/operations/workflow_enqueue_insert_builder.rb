# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds durable inserts for a root workflow enqueue.
        class WorkflowEnqueueInsertBuilder
          def initialize(operation:, enqueue_request:)
            @operation = operation
            @enqueue_request = enqueue_request
          end

          def build
            WorkflowQueueJobInsertBuilder.new(
              namespace:,
              queued_jobs:,
              existing_queue_entries: rows.fetch(:queue_entries)
            ).build.merge(
              workflow_batches: [workflow_batch_row],
              workflow_steps: workflow_step_rows,
              workflow_history: workflow_history_rows
            )
          end

          private

          attr_reader :operation, :enqueue_request

          def namespace = enqueue_request.namespace
          def rows = enqueue_request.rows
          def batch_id = enqueue_request.batch_id
          def queued_jobs = enqueue_request.queued_jobs
          def registration = enqueue_request.registration
          def now = enqueue_request.now

          def workflow_batch_row
            jobs_by_id = queued_jobs.to_h { |job| [job.id, job] }
            Workflow::Batch.new(
              id: batch_id,
              job_ids: jobs_by_id.keys,
              created_at: now,
              updated_at: now,
              max_size: operation.store.send(:max_batch_size)
            ).then do |batch|
              WorkflowBatchRecord.new(
                namespace:,
                batch:,
                registration:,
                jobs_by_id:
              ).to_h
            end
          end

          def workflow_step_rows
            queued_jobs_by_id = queued_jobs.to_h { |job| [job.id, job] }
            registration.step_job_ids.each_with_index.map do |(step_id, job_id), index|
              workflow_step_row(queued_jobs_by_id, step_id, job_id, index + 1)
            end.freeze
          end

          def workflow_history_rows
            history_rows = []
            working_rows = rows.merge(workflow_history: rows.fetch(:workflow_history, []).dup)
            working_history = working_rows.fetch(:workflow_history)

            workflow_row = operation.send(
              :build_workflow_history_row,
              rows: working_rows,
              namespace:,
              batch_id:,
              entry: workflow_entry
            )
            history_rows << workflow_row
            working_history << workflow_row

            registration.step_job_ids.each do |step_id, job_id|
              step_row = operation.send(
                :build_workflow_history_row,
                rows: working_rows,
                namespace:,
                batch_id:,
                entry: step_entry(step_id, job_id)
              )
              history_rows << step_row
              working_history << step_row
            end
            history_rows.freeze
          end

          def workflow_entry
            Workflow::HistoryEntry.new(
              kind: :workflow,
              action: :workflow_registered,
              occurred_at: now,
              workflow_id: registration.workflow_id,
              workflow_family: registration.workflow_family,
              workflow_version: registration.workflow_version,
              batch_id:,
              details: { 'step_count' => registration.step_job_ids.length }
            )
          end

          def step_entry(step_id, job_id)
            Workflow::HistoryEntry.new(
              kind: :step,
              action: :queued,
              occurred_at: now,
              workflow_id: registration.workflow_id,
              workflow_family: registration.workflow_family,
              workflow_version: registration.workflow_version,
              batch_id:,
              step_id:,
              job_id:,
              details: { 'from_state' => 'submission' }
            )
          end

          def workflow_step_row(queued_jobs_by_id, step_id, job_id, sequence)
            job = queued_jobs_by_id.fetch(job_id)
            {
              namespace:,
              batch_id:,
              step_id:,
              step_sequence: sequence,
              job_id:,
              state: job.state.to_s,
              dependency_payload: PayloadCodec.dump(registration.dependency_job_ids_by_job_id.fetch(job_id, [])),
              metadata_payload: PayloadCodec.dump(PolicyStateRecord.stringify_payload(workflow_metadata(step_id, job_id))),
              updated_at: job.updated_at
            }.freeze
          end

          def workflow_metadata(step_id, job_id)
            {
              'approval_requirement' => registration.approval_requirements_by_job_id[job_id],
              'interaction_requirement' => registration.interaction_requirements_by_job_id[job_id],
              'compensation_job_id' => registration.compensation_jobs_by_step_id[step_id],
              'child_workflow_id' => registration.child_workflow_ids_by_step_id[step_id]
            }
          end
        end
      end
    end
  end
end
