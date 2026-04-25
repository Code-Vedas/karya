# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Owner-local workflow batch creation and inspection support.
        module BatchSupport
          def batch_snapshot(batch_id:, now:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidBatchError)
            normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)

            @mutex.synchronize do
              batch = fetch_batch(normalized_batch_id)
              job_ids = batch.job_ids
              jobs = fetch_batch_jobs(batch)
              Workflow::BatchSnapshot.new(
                batch_id: batch.id,
                captured_at: normalized_now,
                job_ids:,
                jobs:
              )
            end
          end

          private

          def build_optional_enqueue_batch(batch_id:, jobs:, now:)
            case batch_id
            when NilClass
              nil
            else
              build_enqueue_batch(batch_id:, jobs:, now:)
            end
          end

          def build_enqueue_batch(batch_id:, jobs:, now:)
            batch = Workflow::Batch.new(
              id: batch_id,
              job_ids: jobs.map(&:id),
              created_at: now,
              updated_at: now,
              max_size: max_batch_size
            )
            batch_id = batch.id
            raise Workflow::DuplicateBatchError, "batch #{batch_id.inspect} already exists" if state.batches_by_id.key?(batch_id)

            batch
          end

          def store_optional_batch(batch)
            case batch
            when NilClass
              nil
            else
              store_batch(batch)
            end
          end

          def store_batch(batch)
            state.register_batch(batch)
            state.prune_terminal_batches(completed_batch_retention_limit)
            batch
          end

          def fetch_batch(batch_id)
            state.batches_by_id.fetch(batch_id)
          rescue KeyError => e
            raise Workflow::UnknownBatchError, "batch #{batch_id.inspect} is not registered", cause: e
          end

          def fetch_batch_jobs(batch)
            batch.job_ids.map do |job_id|
              state.jobs_by_id.fetch(job_id) do
                raise Workflow::InvalidBatchError, "batch #{batch.id.inspect} member job #{job_id.inspect} is not registered"
              end
            end
          end
        end
      end
    end
  end
end
