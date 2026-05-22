# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Resolves one bulk-mutation job id and records not-found skips.
        class BulkJobLookup
          def initialize(namespace:, rows:, job_id:, skipped_jobs:)
            @namespace = namespace
            @rows = rows
            @job_id = job_id
            @skipped_jobs = skipped_jobs
          end

          attr_reader :namespace, :rows, :job_id, :skipped_jobs

          def load
            job = JobRuntimeRows.new(namespace:, rows:).job_for(job_id)
            return job if job

            skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :not_found).to_h
            nil
          end
        end
      end
    end
  end
end
