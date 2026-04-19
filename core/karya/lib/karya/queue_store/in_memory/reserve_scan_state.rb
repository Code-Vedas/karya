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
          BackpressureSupport.scope_keys_for(job, job.concurrency_scope).any? do |scope_key|
            policy = @concurrency_policies[scope_key]
            policy && @concurrency_counts.fetch(scope_key, 0) >= policy.limit
          end
        end

        def rate_limited?(job)
          BackpressureSupport.scope_keys_for(job, job.rate_limit_scope).any? do |scope_key|
            policy = @rate_limit_policies[scope_key]
            policy && @rate_limit_counts.fetch(scope_key, 0) >= policy.limit
          end
        end

        private

        def accumulate_concurrency_counts(leases_by_token)
          leases_by_token.each_value { |reservation| increment_concurrency_counts(reservation) }
        end

        def increment_concurrency_counts(reservation)
          job = @state.jobs_by_id.fetch(reservation.job_id)
          BackpressureSupport.scope_keys_for(job, job.concurrency_scope).each do |scope_key|
            next unless @concurrency_policies.key?(scope_key)

            @concurrency_counts[scope_key] += 1
          end
        end
      end
    end
  end
end
