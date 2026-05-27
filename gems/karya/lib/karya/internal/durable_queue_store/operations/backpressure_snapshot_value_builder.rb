# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds the durable backpressure snapshot from normalized runtime rows.
        class BackpressureSnapshotValueBuilder
          # Rebuilds active and blocked concurrency state per configured scope.
          class ConcurrencySnapshotBuilder
            # Counts active reservations once per configured concurrency scope.
            class ActiveCounts
              def initialize(store:, rows:)
                @store = store
                @rows = rows
              end

              attr_reader :store, :rows

              def fetch(scope_key)
                counts.fetch(scope_key, 0)
              end

              private

              def counts
                @counts ||= store.send(:policy_set).concurrency.each_key.to_h do |scope_key|
                  [scope_key, ActiveConcurrencyCounter.new(rows:, scope_key:).count]
                end.freeze
              end
            end

            # Formats one concurrency scope into the public snapshot shape.
            class Entry
              def initialize(job:, queue_entry:, scope_key:, policy:, active_count:)
                @job = job
                @queue_entry = queue_entry
                @scope_key = scope_key
                @policy = policy
                @active_count = active_count
              end

              attr_reader :job, :queue_entry, :scope_key, :policy, :active_count

              def blocked?
                queued_state? &&
                  scoped_job? &&
                  active_count >= policy.limit
              end

              private

              def queued_state?
                RowSupport::QUEUED_STATES.include?(job.state)
              end

              def scoped_job?
                ScopeKeySet.new(job:, explicit_scope: job.concurrency_scope).to_a.include?(scope_key)
              end
            end

            def initialize(store:, rows:, jobs:)
              @store = store
              @rows = rows
              @jobs = jobs
            end

            attr_reader :store, :rows, :jobs

            def to_h
              policies.each_with_object({}) do |(scope_key, policy), snapshot|
                active_count = active_counts.fetch(scope_key)
                snapshot[scope_key] = {
                  scope: policy.scope,
                  limit: policy.limit,
                  active_count:,
                  blocked_count: blocked_count_for(scope_key, policy, active_count)
                }.freeze
              end.freeze
            end

            private

            def active_counts
              @active_counts ||= ActiveCounts.new(store:, rows:)
            end

            def policies
              store.send(:policy_set).concurrency
            end

            def queue_entries
              @queue_entries ||= rows.fetch(:queue_entries)
            end

            def blocked_count_for(scope_key, policy, active_count)
              queue_entries.count do |queue_entry|
                Entry.new(
                  job: jobs.fetch(queue_entry.fetch(:job_id)),
                  queue_entry:,
                  scope_key:,
                  policy:,
                  active_count:
                ).blocked?
              end
            end
          end

          # Rebuilds the durable rate-limit window and blocked counts per scope.
          class RateLimitSnapshotBuilder
            # Shares immutable scope-specific inputs across rate-limit entries.
            class EntryContext
              def initialize(rows:, scope_key:, now:, policy:, operation:)
                @rows = rows
                @scope_key = scope_key
                @now = now
                @policy = policy
                @operation = operation
              end

              attr_reader :rows, :scope_key, :now, :policy, :operation
            end

            # Formats one rate-limit scope into the public snapshot shape.
            class Entry
              def initialize(job:, context:)
                @job = job
                @context = context
              end

              attr_reader :job, :context

              def blocked?
                scoped_job? && operation.send(:rate_limit_blocked?, rows, job, now)
              end

              private

              def scope_key
                context.scope_key
              end

              def rows
                context.rows
              end

              def now
                context.now
              end

              def operation
                context.operation
              end

              def scoped_job?
                ScopeKeySet.new(job:, explicit_scope: job.rate_limit_scope).to_a.include?(scope_key)
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
              policies.each_with_object({}) do |(scope_key, policy), snapshot|
                snapshot[scope_key] = {
                  scope: policy.scope,
                  limit: policy.limit,
                  period: policy.period,
                  window_count: window_count_for(scope_key, policy),
                  blocked_count: blocked_count_for(scope_key, policy)
                }.freeze
              end.freeze
            end

            private

            def policies
              store.send(:policy_set).rate_limits
            end

            def queue_entries
              @queue_entries ||= rows.fetch(:queue_entries)
            end

            def window_count_for(scope_key, policy)
              operation.send(:rate_limit_admissions, rows, scope_key, now, policy).length
            end

            def blocked_count_for(scope_key, policy)
              context = EntryContext.new(rows:, scope_key:, now:, policy:, operation:)
              queue_entries.count do |queue_entry|
                Entry.new(
                  job: jobs.fetch(queue_entry.fetch(:job_id)),
                  context:
                ).blocked?
              end
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

          def build
            {
              captured_at: now.dup.freeze,
              concurrency: ConcurrencySnapshotBuilder.new(store:, rows:, jobs:).to_h,
              rate_limits: RateLimitSnapshotBuilder.new(store:, rows:, jobs:, now:, operation:).to_h
            }.freeze
          end
        end
      end
    end
  end
end
