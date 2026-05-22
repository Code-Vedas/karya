# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Rebuilds durable job-related row groups after one job transition.
        class JobRuntimeRows
          def initialize(namespace:, rows:)
            @namespace = namespace
            @rows = rows
          end

          attr_reader :namespace, :rows

          def job_for(job_id)
            job_row = row_index.jobs_by_id[job_id]
            job_row && JobRow.new(row: job_row).to_job
          end

          def deletes_for(job_id:, delete_queue_entries:, delete_reservations:)
            {}.tap do |deletes|
              queue_entries = row_index.queue_entries_for(job_id)
              deletes[:queue_entries] = queue_entries if delete_queue_entries && !queue_entries.empty?

              reservations = row_index.reservations_for(job_id)
              deletes[:reservations] = reservations if delete_reservations && !reservations.empty?
            end
          end

          def queue_entry_insert_groups_for(job)
            return {} unless %i[queued retry_pending].include?(job.state)

            { queue_entries: [queue_entry_row_for(job, queue_entries)] }
          end

          def enqueue_insert_groups_for(job)
            inserts = { jobs: [job_row_for(job)] }
            inserts[:queue_entries] = [queue_entry_row_for(job, queue_entries)] if %i[queued retry_pending].include?(job.state)
            inserts[:idempotency_keys] = [IdempotencyKeyRecord.new(namespace:, job:).to_h] if job.idempotency_key
            inserts[:uniqueness_keys] = [UniquenessKeyRecord.new(namespace:, job:).to_h] if job.uniqueness_key && job.uniqueness_scope
            inserts.freeze
          end

          def append_enqueued(job)
            rows.merge(
              jobs: rows.fetch(:jobs) + [job_row_for(job)],
              queue_entries: queue_entries + [queue_entry_row_for(job, queue_entries)]
            )
          end

          def replace(job_id:, replacement_job:)
            queue_entries_without_job = queue_entries - row_index.queue_entries_for(job_id)
            queue_entries_after_replace =
              if %i[queued retry_pending].include?(replacement_job.state)
                queue_entries_without_job + [queue_entry_row_for(replacement_job, queue_entries_without_job)]
              else
                queue_entries_without_job
              end

            rows.merge(
              jobs: rows.fetch(:jobs).reject { |row| row.fetch(:job_id) == job_id } + [job_row_for(replacement_job)],
              queue_entries: queue_entries_after_replace,
              reservations: rows.fetch(:reservations) - row_index.reservations_for(job_id)
            )
          end

          private

          def row_index
            @row_index ||= RowIndex.new(rows:)
          end

          def queue_entries
            rows.fetch(:queue_entries)
          end

          def job_row_for(job)
            JobRecord.new(namespace:, job:).to_h
          end

          def queue_entry_row_for(job, entries)
            QueueEntryRecord.new(
              namespace:,
              job:,
              insertion_sequence: QueueEntrySequence.new(queue_entries: entries, queue: job.queue).next_value
            ).to_h
          end
        end
      end
    end
  end
end
