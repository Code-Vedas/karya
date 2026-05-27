# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds the durable circuit-breaker snapshot per configured scope.
        class CircuitBreakerSnapshotBuilder
          # Shares immutable scope-specific inputs across one circuit-breaker snapshot entry.
          class SnapshotContext
            def initialize(builder:, scope_key:, policy:)
              @builder = builder
              @scope_key = scope_key
              @policy = policy
            end

            attr_reader :builder, :scope_key, :policy

            def queue_entries
              builder.rows.fetch(:queue_entries)
            end

            def rows
              builder.rows
            end

            def now
              builder.now
            end

            def operation
              builder.operation
            end
          end

          # Counts queued jobs blocked by one circuit-breaker scope.
          class BlockedJobsCounter
            def initialize(jobs:, context:)
              @jobs = jobs
              @context = context
            end

            attr_reader :jobs, :context

            def count
              queue_entries.count do |queue_entry|
                job = jobs.fetch(queue_entry.fetch(:job_id))
                scoped_job?(job) && operation.send(:circuit_breaker_scope_blocked?, rows, scope_key, now, policy)
              end
            end

            private

            def rows
              context.rows
            end

            def scope_key
              context.scope_key
            end

            def now
              context.now
            end

            def policy
              context.policy
            end

            def queue_entries
              context.queue_entries
            end

            def operation
              context.operation
            end

            def scoped_job?(job)
              ScopeKeySet.new(job:, explicit_scope: nil).to_a.include?(scope_key)
            end
          end

          # Formats one circuit-breaker scope into the public snapshot shape.
          class Entry
            def initialize(jobs:, context:)
              @jobs = jobs
              @context = context
            end

            attr_reader :jobs, :context

            def to_h
              {
                scope: policy.scope,
                state: state.fetch(:state),
                failure_count: failures.length,
                failure_threshold: policy.failure_threshold,
                window: policy.window,
                cooldown: policy.cooldown,
                blocked_count: blocked_count,
                cooldown_until: cooldown_until,
                probe_slots_remaining:
              }.freeze
            end

            private

            def rows
              context.rows
            end

            def scope_key
              context.scope_key
            end

            def policy
              context.policy
            end

            def now
              context.now
            end

            def operation
              context.operation
            end

            def state
              @state ||= operation.send(:breaker_state, rows, scope_key, now, policy)
            end

            def failures
              @failures ||= operation.send(:breaker_failures, rows, scope_key, now, policy)
            end

            def blocked_count
              BlockedJobsCounter.new(
                jobs:,
                context:
              ).count
            end

            def cooldown_until
              state.fetch(:state) == :open ? state[:cooldown_until] : nil
            end

            def probe_slots_remaining
              return unless state.fetch(:state) == :half_open

              policy.half_open_limit - operation.send(:filtered_probe_tokens, rows, scope_key).length
            end
          end

          def initialize(store:, rows:, jobs:, now:, operation:)
            @store = store
            @rows = rows
            @jobs = jobs
            @now = now
            @operation = operation
          end

          attr_reader :store, :rows, :jobs, :now, :operation

          def to_h
            store.send(:circuit_breaker_policy_set).policies.each_with_object({}) do |(scope_key, policy), snapshot|
              context = SnapshotContext.new(
                builder: self,
                scope_key:,
                policy:
              )
              snapshot[scope_key] = Entry.new(
                jobs:,
                context:
              ).to_h
            end.freeze
          end
        end
      end
    end
  end
end
