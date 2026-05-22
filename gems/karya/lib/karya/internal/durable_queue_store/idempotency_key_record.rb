# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Builds one durable idempotency-key ownership row from a canonical job.
      class IdempotencyKeyRecord
        def initialize(namespace:, job:)
          @namespace = namespace
          @job = job
        end

        def to_h
          {
            namespace:,
            idempotency_key: job.idempotency_key,
            job_id: job.id,
            state: job.state.to_s,
            created_at: job.created_at,
            updated_at: job.updated_at
          }
        end

        private

        attr_reader :job, :namespace
      end
    end
  end
end
