# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Snapshot of backpressure state reused during one reserve scan.
      class ReserveScanState
        def initialize(policy_set:, state:)
          @state = state
          @concurrency_counts = Hash.new(0)
          accumulate_concurrency_counts(@state.reservations_by_token)
          accumulate_concurrency_counts(@state.executions_by_token)
          @concurrency_limits = policy_set.concurrency.transform_values(&:limit)
          @rate_limit_counts = state.rate_limit_admissions_by_key.transform_values(&:length)
          @rate_limit_limits = policy_set.rate_limits.transform_values(&:limit)
        end

        def concurrency_blocked?(job)
          concurrency_key = job.concurrency_key
          return false unless concurrency_key

          limit = @concurrency_limits[concurrency_key]
          limit && @concurrency_counts.fetch(concurrency_key, 0) >= limit
        end

        def rate_limited?(job)
          rate_limit_key = job.rate_limit_key
          return false unless rate_limit_key

          limit = @rate_limit_limits[rate_limit_key]
          limit && @rate_limit_counts.fetch(rate_limit_key, 0) >= limit
        end

        private

        def accumulate_concurrency_counts(leases_by_token)
          jobs_by_id = @state.jobs_by_id

          leases_by_token.each_value do |reservation|
            concurrency_key = jobs_by_id.fetch(reservation.job_id).concurrency_key
            next unless concurrency_key

            @concurrency_counts[concurrency_key] += 1
          end
        end
      end
    end
  end
end
