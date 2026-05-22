# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds durable stuck-job snapshot entries from policy-state rows.
        class StuckJobsSnapshotBuilder
          # Formats one stuck-job recovery payload into the public snapshot shape.
          class SnapshotEntry
            def initialize(job_id:, job:, payload:)
              @job_id = job_id
              @job = job
              @payload = payload
            end

            attr_reader :job_id, :job, :payload

            def to_h
              {
                job_id:,
                queue: job.queue,
                handler: job.handler,
                state: job.state,
                attempt: job.attempt,
                recovery_count: payload['recovery_count'] || payload[:recovery_count],
                last_recovered_at: payload['last_recovered_at'] || payload[:last_recovered_at],
                last_recovery_reason: payload['last_recovery_reason'] || payload[:last_recovery_reason]
              }.freeze
            end
          end

          def initialize(rows:, jobs:)
            @rows = rows
            @jobs = jobs
          end

          attr_reader :rows, :jobs

          def to_h
            rows.fetch(:policy_state, []).each_with_object({}) do |row, snapshot|
              next unless row.fetch(:policy_kind) == 'stuck_job_recovery'

              job_id = row.fetch(:scope_value)
              job = jobs[job_id]
              next unless job

              snapshot[job_id] = SnapshotEntry.new(job_id:, job:, payload: PolicyStateRow.new(row:).payload).to_h
            end.freeze
          end
        end
      end
    end
  end
end
