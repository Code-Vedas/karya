# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Merges recovered-running-job metadata back into durable policy rows.
        class StuckJobRecoveryMerger
          # Finds the current stuck-job recovery row for one job id.
          class ExistingRowFinder
            def initialize(rows:, job_id:)
              @rows = rows
              @job_id = job_id
            end

            attr_reader :rows, :job_id

            def find
              rows.fetch(:policy_state).find do |row|
                row.fetch(:policy_kind) == 'stuck_job_recovery' && row.fetch(:scope_value) == job_id
              end
            end
          end

          # Rebuilds one stuck-job recovery policy row for a recovered job.
          class Entry
            def initialize(namespace:, job:, existing_row:, now:)
              @namespace = namespace
              @job = job
              @existing_row = existing_row
              @now = now
            end

            attr_reader :namespace, :job, :existing_row, :now

            def to_h
              PolicyStateRecord.new(
                namespace:,
                policy_kind: 'stuck_job_recovery',
                scope: { kind: 'job', value: job.id },
                state_payload: {
                  recovery_count: existing_recovery_count + 1,
                  last_recovered_at: now,
                  last_recovery_reason: RecoverySupport::STUCK_JOB_RECOVERY_REASON
                },
                updated_at: now
              ).to_h
            end

            private

            def existing_payload
              @existing_payload ||= PolicyStateRow.new(row: existing_row).payload
            end

            def existing_recovery_count
              existing_payload['recovery_count'] || existing_payload[:recovery_count] || 0
            end
          end

          def initialize(rows:, recovered_running_jobs:, now:)
            @rows = rows
            @recovered_running_jobs = recovered_running_jobs
            @now = now
          end

          attr_reader :rows, :recovered_running_jobs, :now

          def merge
            rows.merge(policy_state:)
          end

          private

          def namespace
            rows.fetch(:namespace)
          end

          def policy_state
            recovered_running_jobs.reduce(rows.fetch(:policy_state).dup) do |policy_rows, job|
              update_policy_rows(policy_rows, job)
            end
          end

          def update_policy_rows(policy_rows, job)
            job_id = job.id
            filtered_rows = policy_rows.reject do |row|
              row.fetch(:policy_kind) == 'stuck_job_recovery' && row.fetch(:scope_value) == job_id
            end
            filtered_rows << Entry.new(
              namespace:,
              job:,
              existing_row: existing_row_for(job_id),
              now:
            ).to_h
          end

          def existing_row_for(job_id)
            ExistingRowFinder.new(rows:, job_id:).find
          end
        end
      end
    end
  end
end
