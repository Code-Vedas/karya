# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Read-only backpressure inspection helpers.
        module BackpressureSnapshotSupport
          # Immutable snapshot row for one concurrency policy scope.
          class ConcurrencySnapshot
            def self.from_policy(policy, active_count:, blocked_count:)
              new(
                scope: policy.scope,
                limit: policy.limit,
                active_count:,
                blocked_count:
              )
            end

            def initialize(scope:, limit:, active_count:, blocked_count:)
              @scope = scope
              @limit = limit
              @active_count = active_count
              @blocked_count = blocked_count
            end

            def to_h
              {
                scope: @scope,
                limit: @limit,
                active_count: @active_count,
                blocked_count: @blocked_count
              }.freeze
            end
          end

          # Immutable snapshot row for one rate-limit policy scope.
          class RateLimitSnapshot
            def self.from_policy(policy, window_count:, blocked_count:)
              new(
                scope: policy.scope,
                limit: policy.limit,
                period: policy.period,
                window_count:,
                blocked_count:
              )
            end

            def initialize(scope:, limit:, period:, window_count:, blocked_count:)
              @scope = scope
              @limit = limit
              @period = period
              @window_count = window_count
              @blocked_count = blocked_count
            end

            def to_h
              {
                scope: @scope,
                limit: @limit,
                period: @period,
                window_count: @window_count,
                blocked_count: @blocked_count
              }.freeze
            end
          end

          private_constant :ConcurrencySnapshot, :RateLimitSnapshot

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
              snapshot[scope_key] = ConcurrencySnapshot.from_policy(
                policy,
                active_count: counts.fetch(scope_key, 0),
                blocked_count: blocked_counts.fetch([:concurrency, scope_key], 0)
              ).to_h
            end.freeze
          end

          def snapshot_rate_limits(blocked_counts, rate_limit_counts)
            policy_set.rate_limits.each_with_object({}) do |(scope_key, policy), snapshot|
              snapshot[scope_key] = RateLimitSnapshot.from_policy(
                policy,
                window_count: rate_limit_counts.fetch(scope_key, 0),
                blocked_count: blocked_counts.fetch([:rate_limit, scope_key], 0)
              ).to_h
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
            count_blocked_scopes(
              counts,
              scope_type: :concurrency,
              job:,
              job_scope: job.concurrency_scope,
              active_counts: concurrency_counts
            )
            count_blocked_scopes(
              counts,
              scope_type: :rate_limit,
              job:,
              job_scope: job.rate_limit_scope,
              active_counts: rate_limit_counts
            )

            nil
          end

          def count_blocked_scopes(counts, scope_type:, job:, job_scope:, active_counts:)
            policies = scope_type == :concurrency ? policy_set.concurrency : policy_set.rate_limits
            BackpressureSupport.each_scope_key(job, job_scope) do |scope_key|
              policy = policies[scope_key]
              next unless policy
              next unless active_counts.fetch(scope_key, 0) >= policy.limit

              counts[[scope_type, scope_key]] += 1
            end
          end
        end
      end
    end
  end
end
