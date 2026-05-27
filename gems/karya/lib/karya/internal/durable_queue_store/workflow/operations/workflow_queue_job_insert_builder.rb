# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds durable job, queue-entry, idempotency, and uniqueness inserts for queued workflow jobs.
        class WorkflowQueueJobInsertBuilder
          def initialize(namespace:, queued_jobs:, existing_queue_entries:)
            @namespace = namespace
            @queued_jobs = queued_jobs
            @queue_entries = existing_queue_entries.dup
          end

          def build
            queued_jobs.each_with_object(empty_inserts) do |job, inserts|
              inserts[:jobs] << JobRecord.new(namespace:, job:).to_h
              inserts[:queue_entries] << queue_entry_row(job)
              inserts[:idempotency_keys] << IdempotencyKeyRecord.new(namespace:, job:).to_h if job.idempotency_key
              inserts[:uniqueness_keys] << UniquenessKeyRecord.new(namespace:, job:).to_h if job.uniqueness_key && job.uniqueness_scope
            end
          end

          private

          attr_reader :namespace, :queued_jobs, :queue_entries

          def empty_inserts
            { jobs: [], queue_entries: [], idempotency_keys: [], uniqueness_keys: [] }
          end

          def queue_entry_row(job)
            queue_entry = QueueEntryRecord.new(
              namespace:,
              job:,
              insertion_sequence: QueueEntrySequence.new(queue_entries:, queue: job.queue).next_value
            ).to_h
            queue_entries << queue_entry
            queue_entry
          end
        end
      end
    end
  end
end
