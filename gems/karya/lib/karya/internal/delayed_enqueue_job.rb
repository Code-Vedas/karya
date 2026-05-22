# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Dispatches one Karya delayed-enqueue payload back into the active queue.
    class DelayedEnqueueJob
      class << self
        def perform(payload)
          request = deserialize_request(payload)
          dispatched_at = Time.now.utc

          Karya.enqueue(
            queue: request.fetch('queue'),
            handler: request.fetch('handler'),
            arguments: request.fetch('arguments'),
            now: dispatched_at,
            job_id: request.fetch('job_id'),
            created_at: request.fetch('created_at'),
            enqueued_at: dispatched_at
          )
        end

        def serialize_request(queue:, handler:, arguments:, job_id:, created_at:, scheduled_at:)
          DurableQueueStore::PayloadCodec.dump(
            {
              'queue' => queue,
              'handler' => handler,
              'arguments' => normalized_arguments(arguments),
              'job_id' => job_id,
              'created_at' => created_at,
              'scheduled_at' => scheduled_at
            }
          )
        end

        def deserialize_request(payload)
          DurableQueueStore::PayloadCodec.decode(payload)
        end

        private

        def normalized_arguments(arguments)
          Karya::Internal::ImmutableArgumentGraph.new(
            arguments,
            error_class: Karya::InvalidJobAttributeError
          ).normalize
        end
      end
    end
  end
end
