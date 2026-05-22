# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Validates workflow enqueue requests and simulates accepted row growth.
        class WorkflowEnqueueValidator
          def initialize(rows:, now:)
            @rows = rows
            @now = now
          end

          def validate(jobs)
            accepted_jobs = []
            accepted_job_ids = {}
            mutated_rows = rows
            jobs.each do |job|
              validate_job(job)
              evaluator = UniquenessEvaluator.new(rows: mutated_rows, now:)
              evaluator.raise_duplicate_enqueue_error(evaluator.decision_for(job:))
              job_id = job.id
              raise DuplicateJobError, "job #{job_id.inspect} is already present in the queue store" if accepted_job_ids.key?(job_id)

              queued_job = job.transition_to(:queued, updated_at: now)
              accepted_jobs << queued_job
              accepted_job_ids[job_id] = true
              mutated_rows = append_enqueued_rows(mutated_rows, queued_job)
            end
            accepted_jobs
          end

          private

          attr_reader :rows, :now

          def validate_job(job)
            raise InvalidEnqueueError, 'jobs entries must be Karya::Job' unless job.is_a?(Job)
            raise InvalidEnqueueError, 'job must be in :submission state before enqueue' unless job.state == :submission
          end

          def append_enqueued_rows(current_rows, queued_job)
            namespace = current_rows.fetch(:namespace)
            queue_entries = current_rows.fetch(:queue_entries)
            queue_entry_row = QueueEntryRecord.new(
              namespace:,
              job: queued_job,
              insertion_sequence: Operations::QueueEntrySequence.new(
                queue_entries:,
                queue: queued_job.queue
              ).next_value
            ).to_h
            current_rows.merge(
              jobs: current_rows.fetch(:jobs) + [JobRecord.new(namespace:, job: queued_job).to_h],
              queue_entries: queue_entries + [queue_entry_row]
            )
          end
        end
      end
    end
  end
end
