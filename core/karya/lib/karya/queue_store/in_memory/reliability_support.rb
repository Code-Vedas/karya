# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Circuit-breaker and stuck-job tracking helpers.
      module ReliabilitySupport
        COUNTED_FAILURE_CLASSIFICATIONS = %i[error timeout].freeze
        STUCK_JOB_RECOVERY_REASON = 'running_lease_expired'

        private

        def prepare_reliability_snapshot(now)
          expired_reservations = collect_expired_leases(state.reservations_by_token, state.reservation_tokens_in_order, now)
          expired_executions = collect_expired_leases(state.executions_by_token, state.execution_tokens_in_order, now)
          expired_reservations.each { |reservation| requeue_expired_reservation(reservation, now) }
          expired_executions.each { |reservation| requeue_expired_execution(reservation, now) }
          prune_stale_rate_limit_admissions(now)
          synchronize_circuit_breakers(now)
          nil
        end

        def synchronize_circuit_breakers(now)
          circuit_breaker_policy_set.policies.each_key { |scope_key| circuit_breaker_state_for(scope_key, now) }
          nil
        end

        def circuit_breaker_blocked?(job, now)
          blocked = false
          BackpressureSupport.each_scope_key(job, nil) do |scope_key|
            policy = circuit_breaker_policy_set.policies[scope_key]
            next unless policy
            next unless circuit_breaker_scope_blocked?(scope_key, policy, now)

            blocked = true
            break
          end
          blocked
        end

        def circuit_breaker_scope_blocked?(scope_key, policy, now)
          state_name = circuit_breaker_state_for(scope_key, now).fetch(:state)
          return true if state_name == :open
          return false unless state_name == :half_open

          half_open_probe_count(scope_key) >= policy.half_open_limit
        end

        def circuit_breaker_state_for(scope_key, now)
          policy = circuit_breaker_policy_set.policies.fetch(scope_key)
          prune_breaker_failures(scope_key, policy, now)
          prune_half_open_probe_admissions(scope_key)
          breaker_states = state.breaker_states_by_scope
          current_state = breaker_states[scope_key]

          if current_state && current_state[:state] == :open && current_state[:cooldown_until] <= now
            current_state = { state: :half_open, cooldown_until: nil }.freeze
            breaker_states[scope_key] = current_state
            state.half_open_probe_admissions_by_scope[scope_key] = []
          end

          current_state || CLOSED_BREAKER_STATE
        end

        CLOSED_BREAKER_STATE = { state: :closed, cooldown_until: nil }.freeze
        private_constant :CLOSED_BREAKER_STATE

        def prune_breaker_failures(scope_key, policy, now)
          timestamps = state.breaker_failures_for(scope_key)
          cutoff_time = now - policy.window
          timestamps.reject! { |timestamp| timestamp <= cutoff_time }
          state.breaker_failures_by_scope.delete(scope_key) if timestamps.empty?
          timestamps
        end

        def prune_half_open_probe_admissions(scope_key)
          probe_admissions = state.half_open_probe_admissions_by_scope
          admissions = probe_admissions.fetch(scope_key, [])
          admissions.select! { |token| active_probe_token?(token) }
          probe_admissions.delete(scope_key) if admissions.empty?
          admissions
        end

        def active_probe_token?(token)
          state.reservations_by_token.key?(token) || state.executions_by_token.key?(token)
        end

        def half_open_probe_count(scope_key)
          prune_half_open_probe_admissions(scope_key).length
        end

        def register_half_open_probe(job, reservation_token, now)
          BackpressureSupport.each_scope_key(job, nil) do |scope_key|
            policy = circuit_breaker_policy_set.policies[scope_key]
            next unless policy
            next unless circuit_breaker_state_for(scope_key, now).fetch(:state) == :half_open

            state.half_open_probe_admissions_for(scope_key) << reservation_token
          end

          nil
        end

        def record_execution_success(job, now)
          BackpressureSupport.each_scope_key(job, nil) do |scope_key|
            next unless circuit_breaker_policy_set.policies[scope_key]
            next unless circuit_breaker_state_for(scope_key, now).fetch(:state) == :half_open

            close_circuit_breaker(scope_key)
          end
          clear_stuck_job_recovery(job.id)
          nil
        end

        def record_execution_failure(job, failure_classification, now)
          return nil unless COUNTED_FAILURE_CLASSIFICATIONS.include?(failure_classification)

          BackpressureSupport.each_scope_key(job, nil) do |scope_key|
            policy = circuit_breaker_policy_set.policies[scope_key]
            next unless policy

            state_name = circuit_breaker_state_for(scope_key, now).fetch(:state)
            if state_name == :half_open
              reopen_circuit_breaker(scope_key, now, policy)
            else
              prune_breaker_failures(scope_key, policy, now)
              failure_timestamps = state.breaker_failures_for(scope_key)
              failure_timestamps << now
              open_circuit_breaker(scope_key, now, policy) if failure_timestamps.length >= policy.failure_threshold
            end
          end

          nil
        end

        def open_circuit_breaker(scope_key, now, policy)
          state.breaker_states_by_scope[scope_key] = {
            state: :open,
            cooldown_until: now + policy.cooldown
          }.freeze
          state.clear_half_open_probe_admissions(scope_key)
          nil
        end

        def reopen_circuit_breaker(scope_key, now, policy)
          state.breaker_failures_by_scope[scope_key] = [now]
          open_circuit_breaker(scope_key, now, policy)
        end

        def close_circuit_breaker(scope_key)
          state.breaker_states_by_scope.delete(scope_key)
          state.breaker_failures_by_scope.delete(scope_key)
          state.clear_half_open_probe_admissions(scope_key)
          nil
        end

        def register_stuck_job_recovery(job, now)
          state.register_stuck_job_recovery(job_id: job.id, now:, reason: STUCK_JOB_RECOVERY_REASON)
          nil
        end

        def clear_stuck_job_recovery(job_id)
          state.stuck_job_recoveries_by_id.delete(job_id)
        end
      end
    end
  end
end
