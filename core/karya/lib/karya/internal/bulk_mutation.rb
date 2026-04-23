# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../queue_store/bulk_mutation_report'

module Karya
  module Internal
    # Shared helpers for bounded bulk mutation reports.
    module BulkMutation
      # Iterates requested job ids and marks duplicate requests.
      class RequestedJobIds
        def initialize(job_ids)
          @job_ids = job_ids
          @seen_job_ids = {}
        end

        def each
          job_ids.each do |job_id|
            duplicate_request = duplicate_request?(job_id)
            yield job_id, duplicate_request
          end
        end

        private

        attr_reader :job_ids, :seen_job_ids

        def duplicate_request?(job_id)
          duplicate_request = seen_job_ids.key?(job_id)
          seen_job_ids[job_id] = true
          duplicate_request
        end
      end

      # Frozen skipped-job entry for a bulk mutation report.
      class SkippedJob
        def initialize(job_id:, reason:, state: nil)
          @job_id = job_id
          @reason = reason
          @state = state
        end

        def to_h
          { job_id:, reason:, state: }.freeze
        end

        private

        attr_reader :job_id, :reason, :state
      end

      # Builds one immutable bulk mutation report from explicit requested ids.
      class ReportBuilder
        def initialize(action:, job_ids:, now:)
          @action = action
          @job_ids = job_ids
          @now = now
        end

        def to_report
          changed_jobs = []
          skipped_jobs = []
          RequestedJobIds.new(job_ids).each do |job_id, duplicate_request|
            if duplicate_request
              skipped_jobs << SkippedJob.new(job_id:, reason: :duplicate_request).to_h
            else
              yield job_id, changed_jobs, skipped_jobs
            end
          end
          QueueStore::BulkMutationReport.new(action:, performed_at: now, requested_job_ids: job_ids, changed_jobs:, skipped_jobs:)
        end

        private

        attr_reader :action, :job_ids, :now
      end
    end
  end
end
