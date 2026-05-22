# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Row-native workflow durable operations layered on top of the shared queue engine.
      module Operations
        WORKFLOW_OPERATION_CONSTANTS = %i[
          WorkflowOperationSupport
          WorkflowStepBulkOperation
          EnqueueWorkflow
          WorkflowSnapshot
          WorkflowHistory
          QueryWorkflow
          DeliverWorkflowSignal
          DeliverWorkflowEvent
          PauseWorkflow
          ResumeWorkflow
          ApproveWorkflowCheckpoints
          RejectWorkflowCheckpoints
          EnqueueChildWorkflow
          SyncChildWorkflows
          RollbackWorkflow
          RetryWorkflowSteps
          DeadLetterWorkflowSteps
          ReplayWorkflowSteps
          RetryDeadLetterWorkflowSteps
          DiscardWorkflowSteps
        ].freeze
        private_constant :WORKFLOW_OPERATION_CONSTANTS

        WORKFLOW_OPERATION_FILES = %w[
          workflow/operations/workflow_operation_support.rb
          workflow/operations/enqueue_workflow.rb
          workflow/operations/workflow_snapshot.rb
          workflow/operations/workflow_history.rb
          workflow/operations/query_workflow.rb
          workflow/operations/deliver_workflow_signal.rb
          workflow/operations/deliver_workflow_event.rb
          workflow/operations/pause_workflow.rb
          workflow/operations/resume_workflow.rb
          workflow/operations/approve_workflow_checkpoints.rb
          workflow/operations/reject_workflow_checkpoints.rb
          workflow/operations/enqueue_child_workflow.rb
          workflow/operations/sync_child_workflows.rb
          workflow/operations/rollback_workflow.rb
          workflow/operations/workflow_step_bulk_operation.rb
          workflow/operations/retry_workflow_steps.rb
          workflow/operations/dead_letter_workflow_steps.rb
          workflow/operations/replay_workflow_steps.rb
          workflow/operations/retry_dead_letter_workflow_steps.rb
          workflow/operations/discard_workflow_steps.rb
        ].freeze
        private_constant :WORKFLOW_OPERATION_FILES

        def self.load_workflow_operation_classes!
          WORKFLOW_OPERATION_CONSTANTS.each do |name|
            remove_const(name)
          rescue NameError
            nil
          end

          WORKFLOW_OPERATION_FILES.each do |relative_path|
            load File.expand_path(relative_path, __dir__)
          end
        end

        load_workflow_operation_classes!
      end
    end
  end
end
