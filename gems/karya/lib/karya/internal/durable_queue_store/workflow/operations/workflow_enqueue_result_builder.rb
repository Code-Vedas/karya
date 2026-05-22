# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds the durable operation result for workflow enqueue-style mutations.
        class WorkflowEnqueueResultBuilder
          def initialize(now:, action:, queued_jobs:, inserts:)
            @now = now
            @action = action
            @queued_jobs = queued_jobs
            @inserts = inserts
          end

          def build
            OperationResult.new(
              value: WorkflowFlowReportBuilder.new(
                action:,
                now:,
                requested_job_ids: queued_jobs.map(&:id),
                changed_jobs: queued_jobs,
                skipped_jobs: []
              ).build,
              mutation_plan: MutationPlan.new(inserts: inserts.transform_values(&:freeze)),
              persist: true
            )
          end

          private

          attr_reader :now, :action, :queued_jobs, :inserts
        end
      end
    end
  end
end
