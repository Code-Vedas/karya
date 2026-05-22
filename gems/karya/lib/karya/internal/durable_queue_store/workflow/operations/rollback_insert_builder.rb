# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'workflow_queue_job_insert_builder'
require_relative 'workflow_enqueue_insert_builder'

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds durable rows for one validated workflow rollback request.
        class RollbackInsertBuilder
          def initialize(operation:, namespace:, rollback_request:)
            @operation = operation
            @namespace = namespace
            @rollback_request = rollback_request
          end

          def build
            WorkflowQueueJobInsertBuilder.new(
              namespace:,
              queued_jobs: rollback_request.queued_jobs,
              existing_queue_entries: rollback_request.rows.fetch(:queue_entries)
            ).build.tap do |inserts|
              append_rollback_batch_rows(inserts)
              inserts[:policy_state] = [rollback_policy_row]
              inserts[:workflow_history] = rollback_history_rows
            end
          end

          private

          attr_reader :operation, :namespace, :rollback_request

          def append_rollback_batch_rows(inserts)
            queued_jobs = rollback_request.queued_jobs
            rollback_batch_id = rollback_request.rollback_batch_id
            return if queued_jobs.empty?

            enqueue_request = WorkflowEnqueueRequest.new(
              namespace:,
              definition: nil,
              now: rollback_request.now,
              batch_id: rollback_batch_id,
              rows: rollback_request.rows,
              queued_jobs:,
              registration: rollback_registration
            )
            builder = WorkflowEnqueueInsertBuilder.new(operation:, enqueue_request:)
            inserts[:workflow_batches] = [builder.send(:workflow_batch_row)]
            inserts[:workflow_steps] = builder.send(:workflow_step_rows)
          end

          def rollback_registration
            @rollback_registration ||= RollbackRegistrationBuilder.new(
              registration: rollback_request.registration,
              rollback_step_ids: rollback_request.rollback_step_ids,
              queued_jobs: rollback_request.queued_jobs
            ).build
          end

          def rollback_policy_row
            queued_jobs = rollback_request.queued_jobs
            operation.send(
              :build_workflow_rollback_row,
              namespace:,
              batch_id: rollback_request.batch_id,
              rollback_batch_id: rollback_request.rollback_batch_id,
              reason: rollback_request.reason,
              requested_at: rollback_request.now,
              compensation_job_ids: queued_jobs.map(&:id)
            )
          end

          def rollback_history_rows
            queued_jobs = rollback_request.queued_jobs
            rollback_batch_id = rollback_request.rollback_batch_id
            created = queued_jobs.any?
            details = RollbackHistoryDetails.new(queued_jobs:).to_h
            created_batch_id = created ? rollback_batch_id : nil
            boundary_action = created ? :rollback_batch_created : :rollback_noop_boundary
            history_rows = []
            [
              history_row(
                history_rows:,
                action: :rollback_requested,
                child_batch_id: created_batch_id,
                details: details.merge('reason' => rollback_request.reason, 'rollback_batch_created' => created)
              ),
              history_row(
                history_rows:,
                action: boundary_action,
                child_batch_id: created_batch_id,
                details:
              )
            ]
          end

          def history_row(history_rows:, action:, child_batch_id:, details:)
            batch_id = rollback_request.batch_id
            base_rows = rollback_request.rows
            rows = base_rows.merge(workflow_history: base_rows.fetch(:workflow_history) + history_rows)
            row = operation.send(
              :workflow_control_row,
              rows:,
              namespace:,
              batch_id:,
              entry: WorkflowControlEntryBuilder.new(
                registration: rollback_request.registration,
                batch_id:,
                occurred_at: rollback_request.now,
                entry: {
                  kind: :rollback,
                  action:,
                  child_batch_id:,
                  details:
                }
              ).build
            )
            history_rows << row
            row
          end
        end

        # Builds deterministic rollback registration state for compensation batches.
        class RollbackRegistrationBuilder
          def initialize(registration:, rollback_step_ids:, queued_jobs:)
            @registration = registration
            @rollback_step_ids = rollback_step_ids
            @queued_jobs = queued_jobs
          end

          def build
            rollback_step_job_ids = self.rollback_step_job_ids
            WorkflowRuntimeSupport::WorkflowRegistration.new(
              registration.workflow_id,
              registration.workflow_family,
              registration.workflow_version,
              rollback_step_job_ids,
              rollback_step_job_ids.invert.freeze,
              dependency_job_ids_by_job_id.freeze,
              empty_map,
              empty_map,
              empty_map,
              empty_map,
              empty_map
            ).freeze
          end

          private

          attr_reader :registration, :rollback_step_ids, :queued_jobs

          def rollback_step_job_ids
            @rollback_step_job_ids ||= rollback_step_ids.zip(queued_jobs.map(&:id)).to_h.freeze
          end

          def dependency_job_ids_by_job_id
            rollback_step_job_ids.each_cons(2).with_object({}) do |((_first_step_id, first_job_id), (_second_step_id, second_job_id)), dependencies|
              dependencies[second_job_id] = [first_job_id].freeze
            end
          end

          def empty_map
            @empty_map ||= {}.freeze
          end
        end

        # Builds the public rollback history detail payload.
        class RollbackHistoryDetails
          def initialize(queued_jobs:)
            @queued_jobs = queued_jobs
          end

          def to_h
            count = queued_jobs.length
            {
              'compensation_job_count' => count,
              'compensation_job_ids_preview' => queued_jobs.map(&:id).first(20),
              'compensation_job_ids_omitted_count' => [count - 20, 0].max
            }
          end

          private

          attr_reader :queued_jobs
        end
      end
    end
  end
end
