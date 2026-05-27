# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds bulk mutation reports for workflow-scoped durable operations.
        class WorkflowFlowReportBuilder
          def initialize(action:, now:, requested_job_ids:, changed_jobs:, skipped_jobs:)
            @action = action
            @now = now
            @requested_job_ids = requested_job_ids
            @changed_jobs = changed_jobs
            @skipped_jobs = skipped_jobs
          end

          def build
            Karya::QueueStore::Internal::BulkMutationReport.new(
              action:,
              performed_at: now,
              requested_job_ids:,
              changed_jobs:,
              skipped_jobs:
            )
          end

          private

          attr_reader :action, :now, :requested_job_ids, :changed_jobs, :skipped_jobs
        end
      end
    end
  end
end
