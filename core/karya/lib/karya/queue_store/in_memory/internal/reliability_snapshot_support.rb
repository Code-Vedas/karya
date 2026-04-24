# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Read-only reliability inspection helpers.
        module ReliabilitySnapshotSupport
          # Immutable snapshot row for one circuit-breaker policy scope.
          class CircuitBreakerSnapshot
            def self.from_policy(policy, breaker_state:, failure_count:, blocked_count:, probe_slots_remaining:)
              state_name = breaker_state.fetch(:state)

              new({
                scope: policy.scope,
                state: state_name,
                failure_count:,
                failure_threshold: policy.failure_threshold,
                window: policy.window,
                cooldown: policy.cooldown,
                blocked_count:,
                cooldown_until: state_name == :open ? breaker_state[:cooldown_until] : nil,
                probe_slots_remaining:
              }.freeze)
            end

            def initialize(snapshot)
              @snapshot = snapshot
            end

            def to_h
              @snapshot
            end
          end

          # Immutable snapshot row for one recovered stuck job.
          class StuckJobSnapshot
            def self.from_job(job_id, job, recovery_state)
              new({
                job_id:,
                queue: job.queue,
                handler: job.handler,
                state: job.state,
                attempt: job.attempt,
                recovery_count: recovery_state.fetch(:recovery_count),
                last_recovered_at: recovery_state.fetch(:last_recovered_at),
                last_recovery_reason: recovery_state.fetch(:last_recovery_reason)
              }.freeze)
            end

            def initialize(snapshot)
              @snapshot = snapshot
            end

            def to_h
              @snapshot
            end
          end

          private_constant :CircuitBreakerSnapshot, :StuckJobSnapshot

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

              snapshot[job_id] = StuckJobSnapshot.from_job(job_id, job, recovery_state).to_h
            end.freeze
          end

          def build_circuit_breaker_snapshot(scope_key, policy, now, blocked_count)
            breaker_state = circuit_breaker_state_for(scope_key, now)
            state_name = breaker_state.fetch(:state)
            CircuitBreakerSnapshot.from_policy(
              policy,
              breaker_state:,
              failure_count: state.breaker_failures_by_scope.fetch(scope_key, []).length,
              blocked_count:,
              probe_slots_remaining: probe_slots_remaining(scope_key, policy, state_name)
            ).to_h
          end

          def probe_slots_remaining(scope_key, policy, state_name)
            return unless state_name == :half_open

            policy.half_open_limit - half_open_probe_count(scope_key)
          end

          def increment_breaker_blocked_counts(counts, job, now)
            BackpressureSupport.each_scope_key(job, nil) do |scope_key|
              policy = circuit_breaker_policy_set.policies[scope_key]
              next unless policy
              next unless circuit_breaker_scope_blocked?(scope_key, policy, now)

              counts[scope_key] += 1
            end
          end
        end
      end
    end
  end
end
