# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Read-only backpressure inspection helpers.
      module BackpressureSnapshotSupport
        private

        def build_backpressure_snapshot(now)
          concurrency_counts = active_concurrency_counts
          rate_limit_counts = active_rate_limit_counts(now)
          blocked_counts = queued_blocked_counts(concurrency_counts:, rate_limit_counts:)
          captured_at = now.dup.freeze

          {
            captured_at:,
            concurrency: snapshot_concurrency(blocked_counts, concurrency_counts),
            rate_limits: snapshot_rate_limits(blocked_counts, rate_limit_counts)
          }.freeze
        end

        def snapshot_concurrency(blocked_counts, counts)
          policy_set.concurrency.each_with_object({}) do |(scope_key, policy), snapshot|
            scope = policy.scope
            limit = policy.limit
            snapshot[scope_key] = {
              scope:,
              limit:,
              active_count: counts.fetch(scope_key, 0),
              blocked_count: blocked_counts.fetch([:concurrency, scope_key], 0)
            }.freeze
          end.freeze
        end

        def snapshot_rate_limits(blocked_counts, rate_limit_counts)
          policy_set.rate_limits.each_with_object({}) do |(scope_key, policy), snapshot|
            scope = policy.scope
            limit = policy.limit
            period = policy.period
            snapshot[scope_key] = {
              scope:,
              limit:,
              period:,
              window_count: rate_limit_counts.fetch(scope_key, 0),
              blocked_count: blocked_counts.fetch([:rate_limit, scope_key], 0)
            }.freeze
          end.freeze
        end

        def active_concurrency_counts
          counts = Hash.new(0)
          each_active_reservation { |reservation| add_concurrency_counts(counts, reservation) }
          counts
        end

        def each_active_reservation(&block)
          raise ArgumentError, 'each_active_reservation requires a block' unless block

          state.reservations_by_token.each_value(&block)
          state.executions_by_token.each_value(&block)

          nil
        end

        def each_queued_job(&block)
          raise ArgumentError, 'each_queued_job requires a block' unless block

          state.queued_job_ids_by_queue.each_value do |job_ids|
            index = 0
            while index < job_ids.length
              job_id = job_ids[index]
              yield state.jobs_by_id.fetch(job_id)
              index += 1
            end
          end

          nil
        end

        def add_concurrency_counts(counts, reservation)
          job = state.jobs_by_id.fetch(reservation.job_id)
          BackpressureSupport.each_scope_key(job, job.concurrency_scope) do |scope_key|
            next unless policy_set.concurrency.key?(scope_key)

            counts[scope_key] += 1
          end

          nil
        end

        def active_rate_limit_counts(now)
          policy_set.rate_limits.each_with_object(Hash.new(0)) do |(scope_key, policy), counts|
            counts[scope_key] = current_rate_limit_count(scope_key, policy, now)
          end
        end

        def current_rate_limit_count(scope_key, _policy, _now)
          admissions = state.rate_limit_admissions_by_key.fetch(scope_key, [])
          admissions.length
        end

        def queued_blocked_counts(concurrency_counts:, rate_limit_counts:)
          counts = Hash.new(0)
          each_queued_job { |job| add_blocked_counts(counts, job, concurrency_counts:, rate_limit_counts:) }
          counts
        end

        def add_blocked_counts(counts, job, concurrency_counts:, rate_limit_counts:)
          BackpressureSupport.each_scope_key(job, job.concurrency_scope) do |scope_key|
            policy = policy_set.concurrency[scope_key]
            next unless policy

            limit = policy.limit
            next unless concurrency_counts.fetch(scope_key, 0) >= limit

            counts[[:concurrency, scope_key]] += 1
          end

          BackpressureSupport.each_scope_key(job, job.rate_limit_scope) do |scope_key|
            policy = policy_set.rate_limits[scope_key]
            next unless policy

            limit = policy.limit
            next unless rate_limit_counts.fetch(scope_key, 0) >= limit

            counts[[:rate_limit, scope_key]] += 1
          end

          nil
        end
      end
    end
  end
end
