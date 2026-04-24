# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Backpressure policy helpers used during reservation scans.
        module BackpressureSupport
          QUEUE_SCOPE_KEY_PREFIX = 'queue:'
          HANDLER_SCOPE_KEY_PREFIX = 'handler:'
          private_constant :QUEUE_SCOPE_KEY_PREFIX, :HANDLER_SCOPE_KEY_PREFIX

          def each_scope_key(job, explicit_scope)
            raise ArgumentError, 'each_scope_key requires a block' unless block_given?

            queue_key = build_scope_key(QUEUE_SCOPE_KEY_PREFIX, job.queue)
            handler_key = build_scope_key(HANDLER_SCOPE_KEY_PREFIX, job.handler)
            explicit_key = explicit_scope&.key

            yield queue_key
            yield handler_key
            yield explicit_key if explicit_key && explicit_key != queue_key && explicit_key != handler_key

            nil
          end

          def build_scope_key(prefix, value)
            "#{prefix}#{value}"
          end
          module_function :each_scope_key, :build_scope_key

          private

          def record_rate_limit_admission(job, now)
            BackpressureSupport.each_scope_key(job, job.rate_limit_scope) do |scope_key|
              policy = policy_set.rate_limits[scope_key]
              next unless policy

              prune_rate_limit_admissions(scope_key, policy, now, delete_empty: false) << now
            end
          end

          def prune_stale_rate_limit_admissions(now)
            rate_limit_keys = state.rate_limit_admissions_by_key.keys
            rate_limit_keys.each do |rate_limit_key|
              policy = policy_set.rate_limits[rate_limit_key]
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
end
