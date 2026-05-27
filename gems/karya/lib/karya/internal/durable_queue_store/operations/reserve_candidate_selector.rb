# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        class Reserve < Operation
          # Selects the first reservable queue entry that satisfies policy gates.
          class CandidateSelector
            include Operations::RowSupport
            include Operations::BackpressurePolicySupport
            include Operations::ReliabilityPolicySupport

            # Filters and orders queue rows for reserve visibility and handler matching.
            class QueueRowSelector
              # Wraps one durable queue-entry row with reserve visibility rules.
              class QueueEntryView
                def initialize(row:, now:, handler_matcher:)
                  @row = row
                  @now = now
                  @handler_matcher = handler_matcher
                end

                attr_reader :row, :now, :handler_matcher

                def matches_queue?(queue)
                  row.fetch(:queue) == queue &&
                    RESERVABLE_QUEUE_ENTRY_STATES.include?(row.fetch(:state)) &&
                    visible? &&
                    handler_matcher.include?(row.fetch(:handler))
                end

                def sort_key
                  [-row.fetch(:priority), row.fetch(:insertion_sequence)]
                end

                private

                def visible?
                  visible_at = row[:visible_at]
                  !visible_at || visible_at <= now
                end
              end

              RESERVABLE_QUEUE_ENTRY_STATES = %w[queued retry_pending].freeze
              private_constant :RESERVABLE_QUEUE_ENTRY_STATES

              def initialize(queue_entries:, now:, handler_matcher:)
                @queue_entries = queue_entries
                @now = now
                @handler_matcher = handler_matcher
              end

              attr_reader :queue_entries, :now, :handler_matcher

              def rows_for(queue)
                matching_views = queue_entry_views.select { |queue_entry| queue_entry.matches_queue?(queue) }
                matching_views.sort_by(&:sort_key).map(&:row)
              end

              private

              def queue_entry_views
                @queue_entry_views ||= queue_entries.map do |row|
                  QueueEntryView.new(row:, now:, handler_matcher:)
                end
              end
            end

            def initialize(operation:, rows:, reserve_request:)
              @store = operation.store
              @rows = rows
              @reserve_request = reserve_request
            end

            attr_reader :store, :rows, :reserve_request

            def call
              queues.each do |queue|
                candidate = candidate_for_queue(queue)
                return candidate if candidate
              end

              nil
            end

            private

            def queues
              reserve_request.fetch(:queues)
            end

            def now
              reserve_request.fetch(:now)
            end

            def handler_matcher
              reserve_request.fetch(:handler_matcher)
            end

            def paused_queues
              @paused_queues ||= rows.fetch(:policy_state).filter_map do |row|
                row.fetch(:scope_value) if row.fetch(:policy_kind) == 'paused_queue'
              end
            end

            def jobs_by_id_index
              @jobs_by_id_index ||= rows.fetch(:jobs).to_h { |row| [row.fetch(:job_id), row] }
            end

            def candidate_for_queue(queue)
              return if paused_queues.include?(queue)

              queue_row_selector.rows_for(queue).each do |queue_entry|
                candidate = candidate_for_entry(queue_entry)
                return candidate if candidate
              end

              nil
            end

            def candidate_for_entry(queue_entry)
              job_row = jobs_by_id_index.fetch(queue_entry.fetch(:job_id))
              return unless job_row.fetch(:state) == queue_entry.fetch(:state)

              job = JobRow.new(row: job_row).to_job
              return unless workflow_dependencies_satisfied?(rows, job, now:)
              return if concurrency_blocked?(rows, job)
              return if rate_limit_blocked?(rows, job, now)
              return if circuit_breaker_blocked?(job)

              { queue_entry:, job: }
            end

            def queue_row_selector
              @queue_row_selector ||= QueueRowSelector.new(
                queue_entries: rows.fetch(:queue_entries),
                now:,
                handler_matcher:
              )
            end

            def circuit_breaker_blocked?(job)
              ScopeKeySet.new(job:, explicit_scope: nil).to_a.any? do |scope_key|
                policy = store.send(:circuit_breaker_policy_set).policies[scope_key]
                policy && circuit_breaker_scope_blocked?(rows, scope_key, now, policy)
              end
            end
          end
        end
      end
    end
  end
end
