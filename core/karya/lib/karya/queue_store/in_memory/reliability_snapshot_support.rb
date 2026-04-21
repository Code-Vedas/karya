# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Read-only reliability inspection helpers.
      module ReliabilitySnapshotSupport
        private

        def build_reliability_snapshot(now)
          breaker_blocked_counts = queued_breaker_blocked_counts(now)
          {
            captured_at: now.dup.freeze,
            circuit_breakers: snapshot_circuit_breakers(now, breaker_blocked_counts),
            stuck_jobs: snapshot_stuck_jobs
          }.freeze
        end

        def snapshot_circuit_breakers(now, breaker_blocked_counts)
          circuit_breaker_policy_set.policies.each_with_object({}) do |(scope_key, policy), snapshot|
            snapshot[scope_key] = build_circuit_breaker_snapshot(scope_key, policy, now, breaker_blocked_counts.fetch(scope_key, 0))
          end.freeze
        end

        def queued_breaker_blocked_counts(now)
          counts = Hash.new(0)
          each_queued_job { |job| increment_breaker_blocked_counts(counts, job, now) }
          counts
        end

        def snapshot_stuck_jobs
          state.stuck_job_recoveries_by_id.each_with_object({}) do |(job_id, recovery_state), snapshot|
            job = state.jobs_by_id[job_id]
            next unless job

            snapshot[job_id] = build_stuck_job_snapshot(job_id, job, recovery_state)
          end.freeze
        end

        # :reek:FeatureEnvy
        def build_circuit_breaker_snapshot(scope_key, policy, now, blocked_count)
          breaker_state = circuit_breaker_state_for(scope_key, now)
          state_name = breaker_state.fetch(:state)
          scope = policy.scope
          failure_threshold = policy.failure_threshold
          window = policy.window
          cooldown = policy.cooldown
          half_open_limit = policy.half_open_limit
          {
            scope:,
            state: state_name,
            failure_count: state.breaker_failures_by_scope.fetch(scope_key, []).length,
            failure_threshold:,
            window:,
            cooldown:,
            blocked_count:,
            cooldown_until: state_name == :open ? breaker_state[:cooldown_until] : nil,
            probe_slots_remaining: state_name == :half_open ? half_open_limit - half_open_probe_count(scope_key) : nil
          }.freeze
        end

        def increment_breaker_blocked_counts(counts, job, now)
          ReliabilitySupport::BreakerScopeKeys.for(job).each do |scope_key|
            policy = circuit_breaker_policy_set.policies[scope_key]
            next unless policy
            next unless circuit_breaker_scope_blocked?(scope_key, policy, now)

            counts[scope_key] += 1
          end
        end

        # :reek:UtilityFunction
        def build_stuck_job_snapshot(job_id, job, recovery_state)
          {
            job_id:,
            queue: job.queue,
            handler: job.handler,
            state: job.state,
            attempt: job.attempt,
            recovery_count: recovery_state.fetch(:recovery_count),
            last_recovered_at: recovery_state.fetch(:last_recovered_at),
            last_recovery_reason: recovery_state.fetch(:last_recovery_reason)
          }.freeze
        end
      end
    end
  end
end
