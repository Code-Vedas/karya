# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Backpressure policy helpers used during reservation scans.
      module BackpressureSupport
        private

        def concurrency_blocked?(job)
          policy = policy_set.concurrency_policy_for(job.concurrency_key)
          return false unless policy

          active_job_count_for(policy.key) >= policy.limit
        end

        def active_job_count_for(concurrency_key)
          count_jobs_with_key(state.reservations_by_token, concurrency_key) +
            count_jobs_with_key(state.executions_by_token, concurrency_key)
        end

        def count_jobs_with_key(leases_by_token, concurrency_key)
          leases_by_token.each_value.count do |reservation|
            state.jobs_by_id.fetch(reservation.job_id).concurrency_key == concurrency_key
          end
        end

        def rate_limited?(job, now)
          policy = policy_set.rate_limit_policy_for(job.rate_limit_key)
          return false unless policy

          prune_rate_limit_admissions(policy.key, policy, now, delete_empty: true).length >= policy.limit
        end

        def record_rate_limit_admission(job, now)
          policy = policy_set.rate_limit_policy_for(job.rate_limit_key)
          return unless policy

          prune_rate_limit_admissions(policy.key, policy, now, delete_empty: false) << now
        end

        def prune_stale_rate_limit_admissions(now)
          state.rate_limit_admissions_by_key.each_key do |rate_limit_key|
            policy = policy_set.rate_limit_policy_for(rate_limit_key)
            unless policy
              state.delete_rate_limit_key(rate_limit_key)
              next
            end

            prune_rate_limit_admissions(rate_limit_key, policy, now, delete_empty: true)
          end
        end

        def prune_rate_limit_admissions(rate_limit_key, policy, now, delete_empty:)
          admissions = state.rate_limit_admissions_for(rate_limit_key)
          cutoff_time = now - policy.period
          admissions.reject! { |admission_time| admission_time <= cutoff_time }
          if delete_empty && admissions.empty?
            state.delete_rate_limit_key(rate_limit_key)
            admissions = []
          end

          admissions
        end
      end
    end
  end
end
