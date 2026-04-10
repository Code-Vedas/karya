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

        def record_rate_limit_admission(job, now)
          policy = policy_set.rate_limit_policy_for(job.rate_limit_key)
          return unless policy

          prune_rate_limit_admissions(policy.key, policy, now, delete_empty: false) << now
        end

        def prune_stale_rate_limit_admissions(now)
          rate_limit_keys = state.rate_limit_admissions_by_key.keys
          rate_limit_keys.each do |rate_limit_key|
            policy = policy_set.rate_limit_policy_for(rate_limit_key)
            unless policy
              state.delete_rate_limit_key(rate_limit_key)
              next
            end

            prune_rate_limit_admissions(rate_limit_key, policy, now, delete_empty: true)
          end
        end

        def build_reserve_scan_state
          ReserveScanState.new(policy_set:, state:)
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
