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
          # Builds the durable row delta for a successful reservation transition.
          class MutationPlanBuilder
            include Operations::RowSupport
            include Operations::BackpressurePolicySupport
            include Operations::ReliabilityPolicySupport

            def initialize(operation:, context:, outcome:)
              @store = operation.store
              @context = context
              @outcome = outcome
            end

            attr_reader :store, :context, :outcome

            def call
              MutationPlan.new(
                metadata_updates: { reservation_token_sequence: outcome.reservation_token_sequence + 1 },
                inserts: insert_groups,
                updates: update_groups,
                deletes: delete_groups
              )
            end

            private

            def rows
              context.rows
            end

            def namespace
              context.namespace
            end

            def reservation
              outcome.reservation
            end

            def reserved_job
              outcome.reserved_job
            end

            def now
              outcome.now
            end

            def candidate
              outcome.candidate
            end

            def insert_groups
              {
                reservations: [ReservationRecord.new(namespace:, reservation:, phase: :reserved).to_h],
                policy_state: breaker_rows.fetch(:inserts) + rate_limit_rows.fetch(:inserts),
                workflow_history: workflow_history_rows
              }
            end

            def update_groups
              {
                jobs: [JobRecord.new(namespace:, job: reserved_job).to_h],
                workflow_steps: workflow_updates.fetch(:workflow_steps),
                workflow_batches: workflow_updates.fetch(:workflow_batches),
                policy_state: breaker_rows.fetch(:updates) + rate_limit_rows.fetch(:updates)
              }
            end

            def delete_groups
              {
                queue_entries: [candidate.fetch(:queue_entry)],
                policy_state: breaker_rows.fetch(:deletes) + rate_limit_rows.fetch(:deletes)
              }
            end

            def workflow_rows
              @workflow_rows ||= rows.merge(namespace:)
            end

            def workflow_updates
              @workflow_updates ||= workflow_row_updates_for_job(context, workflow_rows, reserved_job)
            end

            def workflow_history_rows
              @workflow_history_rows ||= workflow_history_rows_for_job(workflow_rows, namespace:, replacement_job: reserved_job)
            end

            def breaker_rows
              @breaker_rows ||= breaker_policy_rows(context, rows, reserved_job, now, reservation_token: reservation.token)
            end

            def rate_limit_rows
              @rate_limit_rows ||= rate_limit_policy_rows(context, rows, reserved_job, now)
            end
          end
        end
      end
    end
  end
end
