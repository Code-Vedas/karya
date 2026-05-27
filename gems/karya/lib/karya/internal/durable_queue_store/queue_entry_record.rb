# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Builds one durable queue-membership record from a canonical job.
      class QueueEntryRecord
        def initialize(namespace:, job:, insertion_sequence:)
          @namespace = namespace
          @job = job
          @insertion_sequence = insertion_sequence
        end

        def to_h
          {
            namespace:,
            queue: job.queue,
            job_id: job.id,
            state: job.state.to_s,
            visible_at: visible_at,
            priority: job.priority,
            insertion_sequence:,
            handler: job.handler
          }
        end

        private

        attr_reader :insertion_sequence, :job, :namespace

        def visible_at
          return job.next_retry_at if job.state == :retry_pending

          job.created_at
        end
      end
    end
  end
end
