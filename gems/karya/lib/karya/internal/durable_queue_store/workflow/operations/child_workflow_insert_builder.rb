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
        # Builds child-workflow history detail payloads from parent and child metadata.
        class ChildWorkflowHistoryDetails
          def initialize(parent:, definition:)
            @parent = parent
            @definition = definition
          end

          def to_h
            {
              'parent_step_id' => parent.step_id,
              'child_workflow_id' => definition.id,
              'child_workflow_family' => definition.workflow_family,
              'child_workflow_version' => definition.workflow_version
            }
          end

          private

          attr_reader :parent, :definition
        end

        # Builds durable inserts for one validated child-workflow enqueue.
        class ChildWorkflowInsertBuilder
          def initialize(operation:, namespace:, child_request:)
            @operation = operation
            @namespace = namespace
            @child_request = child_request
          end

          def build
            WorkflowQueueJobInsertBuilder.new(
              namespace:,
              queued_jobs: child_request.queued_jobs,
              existing_queue_entries: child_request.rows.fetch(:queue_entries)
            ).build.merge(
              workflow_batches: [workflow_batch_row],
              workflow_steps: workflow_step_rows,
              policy_state: policy_rows,
              workflow_history: history_rows
            )
          end

          private

          attr_reader :operation, :namespace, :child_request

          def workflow_enqueue_insert_builder
            @workflow_enqueue_insert_builder ||= WorkflowEnqueueInsertBuilder.new(
              operation:,
              enqueue_request: WorkflowEnqueueRequest.new(
                namespace:,
                definition: child_request.definition,
                now: child_request.now,
                batch_id: child_request.binding.batch_id,
                rows: child_request.rows,
                queued_jobs: child_request.queued_jobs,
                registration: child_request.registration
              )
            )
          end

          def workflow_batch_row
            workflow_enqueue_insert_builder.send(:workflow_batch_row)
          end

          def workflow_step_rows
            workflow_enqueue_insert_builder.send(:workflow_step_rows)
          end

          def policy_rows
            parent = child_request.parent
            operation.send(
              :build_workflow_child_relationship_rows,
              namespace:,
              parent: parent.relationship_payload,
              parent_step_id: parent.step_id,
              definition: child_request.definition,
              child_batch_id: child_request.binding.batch_id,
              now: child_request.now
            )
          end

          def history_rows
            parent = child_request.parent
            definition = child_request.definition
            parent_batch_id = parent.batch_id
            [
              operation.send(
                :workflow_control_row,
                rows: child_request.rows,
                namespace:,
                batch_id: parent_batch_id,
                entry: WorkflowControlEntryBuilder.new(
                  registration: parent.registration,
                  batch_id: parent_batch_id,
                  occurred_at: child_request.now,
                  entry: {
                    kind: :child_workflow,
                    action: :child_workflow_enqueued,
                    job_id: parent.job_id,
                    child_batch_id: child_request.binding.batch_id,
                    details: ChildWorkflowHistoryDetails.new(parent:, definition:).to_h
                  }
                ).build
              )
            ]
          end
        end
      end
    end
  end
end
