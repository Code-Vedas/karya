# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Builds one durable job record from the canonical job value object.
      class JobRecord
        def initialize(namespace:, job:)
          @namespace = namespace
          @job = job
        end

        def to_h
          base_attributes
            .merge(scheduling_attributes)
            .merge(identity_attributes)
            .merge(failure_attributes)
        end

        private

        attr_reader :job, :namespace

        def base_attributes
          {
            namespace:,
            job_id: job.id,
            queue: job.queue,
            handler: job.handler,
            arguments_payload: PayloadCodec.dump_job_arguments(job.arguments),
            priority: job.priority,
            state: job.state.to_s,
            attempt: job.attempt,
            visible_at:,
            expires_at: job.expires_at,
            created_at: job.created_at,
            enqueued_at: job.enqueued_at,
            updated_at: job.updated_at
          }
        end

        def scheduling_attributes
          retry_policy = job.retry_policy
          concurrency_scope = job.concurrency_scope
          rate_limit_scope = job.rate_limit_scope

          {
            retry_policy_payload: retry_policy && PayloadCodec.dump(retry_policy),
            execution_timeout_seconds: job.execution_timeout,
            concurrency_scope: concurrency_scope && PayloadCodec.dump(concurrency_scope),
            rate_limit_scope: rate_limit_scope && PayloadCodec.dump(rate_limit_scope),
            lifecycle_extensions_payload: PayloadCodec.dump(lifecycle_extensions)
          }
        end

        def identity_attributes
          {
            idempotency_key: job.idempotency_key,
            uniqueness_key: job.uniqueness_key,
            uniqueness_scope: job.uniqueness_scope&.to_s
          }
        end

        def failure_attributes
          {
            failure_classification: job.failure_classification&.to_s,
            dead_letter_reason: job.dead_letter_reason&.to_s,
            dead_lettered_at: job.dead_lettered_at,
            dead_letter_source_state: job.dead_letter_source_state&.to_s
          }
        end

        def visible_at
          return job.next_retry_at if job.state == :retry_pending

          job.created_at
        end

        def lifecycle_extensions
          job.send(:marshal_dump).fetch(:lifecycle_extensions)
        end
      end
    end
  end
end
