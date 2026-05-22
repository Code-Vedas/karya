# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Workflow control operations persist pause and resume transitions.
      module Operations
        require_relative 'workflow_control_request_builder'
        require_relative 'resume_workflow_mutation_builder'

        # Clears a persisted workflow pause and records the resume control entry.
        class ResumeWorkflow < Operation
          include WorkflowOperationSupport
          include RecoverySupport
          include ReliabilityPolicySupport

          def call(context:)
            control_request = WorkflowControlRequestBuilder.new(
              operation: self,
              context:,
              control_verb: 'be controlled'
            ).build
            OperationResult.new(
              value: WorkflowFlowReportBuilder.new(
                action: :resume_workflow,
                now: control_request.now,
                requested_job_ids: [],
                changed_jobs: [],
                skipped_jobs: []
              ).build,
              mutation_plan: ResumeWorkflowMutationBuilder.new(
                operation: self,
                control_request:
              ).build,
              persist: true
            )
          end
        end
      end
    end
  end
end
