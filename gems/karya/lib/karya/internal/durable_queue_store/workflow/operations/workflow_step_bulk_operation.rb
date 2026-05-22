# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'workflow_step_bulk_request_builder'
require_relative 'workflow_step_bulk_report_builder'

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Shared orchestrator for workflow step bulk-control operations.
        class WorkflowStepBulkOperation < Operation
          # Per-step mutation context passed through workflow bulk operations.
          WorkflowBulkMutation = Struct.new(:job, :rows, :skipped_jobs, :job_id, keyword_init: true)

          include WorkflowOperationSupport

          private

          def workflow_bulk_report(context, action, now, &transition_block)
            request = WorkflowStepBulkRequestBuilder.new(operation: self, context:, action:, now:).build
            accumulator = WorkflowStepBulkAccumulator.new
            report, changed = WorkflowStepBulkReportBuilder.new(
              operation: self,
              request:,
              accumulator:,
              transition_block:
            ).build
            [
              report,
              WorkflowStepBulkPlanBuilder.new(operation: self, accumulator:).build,
              changed
            ]
          end
        end
      end
    end
  end
end
