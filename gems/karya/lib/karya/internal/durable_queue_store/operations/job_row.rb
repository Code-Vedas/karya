# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Decodes one durable job row into a runtime Karya::Job view.
        class JobRow
          def initialize(row:)
            @row = row
          end

          attr_reader :row

          def to_job
            Job.new(**attributes)
          end

          def attributes
            identity_attributes
              .merge(lifecycle_attributes)
              .merge(policy_attributes)
              .merge(outcome_attributes)
          end

          private

          def identity_attributes
            {
              id: row.fetch(:job_id),
              queue: row.fetch(:queue),
              handler: row.fetch(:handler),
              arguments: PayloadCodec.decode(row.fetch(:arguments_payload)),
              priority: row.fetch(:priority)
            }
          end

          def lifecycle_attributes
            retry_policy_payload = row[:retry_policy_payload]
            {
              state: row.fetch(:state),
              attempt: row.fetch(:attempt),
              created_at: row.fetch(:created_at),
              enqueued_at: row.fetch(:enqueued_at),
              updated_at: row.fetch(:updated_at),
              next_retry_at:,
              retry_policy: retry_policy_payload && PayloadCodec.decode(retry_policy_payload),
              execution_timeout: row[:execution_timeout_seconds],
              expires_at: row[:expires_at]
            }
          end

          def policy_attributes
            concurrency_scope = row[:concurrency_scope]
            rate_limit_scope = row[:rate_limit_scope]
            {
              concurrency_scope: concurrency_scope && PayloadCodec.decode(concurrency_scope),
              rate_limit_scope: rate_limit_scope && PayloadCodec.decode(rate_limit_scope),
              idempotency_key: row[:idempotency_key],
              uniqueness_key: row[:uniqueness_key],
              uniqueness_scope: row[:uniqueness_scope]
            }
          end

          def outcome_attributes
            {
              failure_classification: row[:failure_classification],
              dead_letter_reason: row[:dead_letter_reason],
              dead_lettered_at: row[:dead_lettered_at],
              dead_letter_source_state: row[:dead_letter_source_state]
            }
          end

          def next_retry_at
            row[:state].to_sym == :retry_pending ? row[:visible_at] : nil
          end
        end
      end
    end
  end
end
