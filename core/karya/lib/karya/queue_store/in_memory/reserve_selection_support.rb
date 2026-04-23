# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Reservation selection helpers used during queue scans.
      module ReserveSelectionSupport
        # Computes the queue scan order for one reservation attempt.
        class FairQueueOrder
          def initialize(queues:, strategy:, last_reserved_queue:)
            @queues = queues
            @strategy = strategy
            @last_reserved_queue = last_reserved_queue
          end

          def to_a
            return queues unless strategy == :round_robin
            return queues unless queues.length > 1

            last_reserved_queue_index = queues.index(last_reserved_queue)
            return queues unless last_reserved_queue_index

            queues.rotate(last_reserved_queue_index + 1)
          end

          private

          attr_reader :last_reserved_queue, :queues, :strategy
        end

        private_constant :FairQueueOrder

        private

        def find_reserved_job(queues, subscription_key, handler_matcher, reserve_scan_state, now)
          fair_queue_order(queues, subscription_key).each do |queue|
            matched_job_index, matched_job_id = matching_job_for(queue, handler_matcher, reserve_scan_state, now)
            return [queue, matched_job_index, matched_job_id] if matched_job_id
          end

          nil
        end

        def fair_queue_order(queues, subscription_key)
          return queues unless track_fairness_history?(queues)

          FairQueueOrder.new(
            queues:,
            strategy: fairness_policy.strategy,
            last_reserved_queue: state.last_reserved_queue_for(subscription_key)
          ).to_a
        end

        def matching_job_for(queue, handler_matcher, reserve_scan_state, now)
          return nil if state.queue_paused?(queue)

          queue_job_ids = state.queued_job_ids_by_queue.fetch(queue, [])
          selected_job_id = nil
          selected_job_index = nil
          selected_job_priority = nil

          queue_job_ids.each_with_index do |job_id, index|
            queued_job = state.jobs_by_id.fetch(job_id)
            queued_job_priority = queued_job.priority
            next unless handler_matcher.include?(queued_job.handler)
            next if reserve_scan_state.concurrency_blocked?(queued_job)
            next if reserve_scan_state.rate_limited?(queued_job)
            next if circuit_breaker_blocked?(queued_job, now)
            next if selected_job_priority && queued_job_priority <= selected_job_priority

            selected_job_id = job_id
            selected_job_index = index
            selected_job_priority = queued_job_priority
          end

          return nil unless selected_job_id

          [selected_job_index, selected_job_id]
        end
      end
    end
  end
end
