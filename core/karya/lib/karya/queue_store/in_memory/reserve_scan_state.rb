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
          @concurrency_policies = policy_set.concurrency
          @rate_limit_policies = policy_set.rate_limits
          @concurrency_counts = Hash.new(0)
          accumulate_concurrency_counts(@state.reservations_by_token)
          accumulate_concurrency_counts(@state.executions_by_token)
          @rate_limit_counts = state.rate_limit_admissions_by_key.transform_values(&:length)
        end

        def concurrency_blocked?(job)
          blocked = false
          BackpressureSupport.each_scope_key(job, job.concurrency_scope) do |scope_key|
            policy = @concurrency_policies[scope_key]
            next unless policy && @concurrency_counts.fetch(scope_key, 0) >= policy.limit

            blocked = true
            break
          end
          blocked
        end

        def rate_limited?(job)
          rate_limited = false
          BackpressureSupport.each_scope_key(job, job.rate_limit_scope) do |scope_key|
            policy = @rate_limit_policies[scope_key]
            next unless policy && @rate_limit_counts.fetch(scope_key, 0) >= policy.limit

            rate_limited = true
            break
          end
          rate_limited
        end

        private

        def accumulate_concurrency_counts(leases_by_token)
          leases_by_token.each_value { |reservation| increment_concurrency_counts(reservation) }
        end

        def increment_concurrency_counts(reservation)
          job = @state.jobs_by_id.fetch(reservation.job_id)
          BackpressureSupport.each_scope_key(job, job.concurrency_scope) do |scope_key|
            next unless @concurrency_policies.key?(scope_key)

            @concurrency_counts[scope_key] += 1
          end
        end
      end
    end
  end
end
