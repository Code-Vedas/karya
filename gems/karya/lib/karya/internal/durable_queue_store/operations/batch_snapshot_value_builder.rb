# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Rebuilds one public batch snapshot from durable workflow rows.
        class BatchSnapshotValueBuilder
          def initialize(rows:, batch_id:, captured_at:)
            @rows = rows
            @batch_id = batch_id
            @captured_at = captured_at
          end

          def build
            batch = WorkflowBatchBuilder.new(rows:, batch_id:).build
            Workflow::BatchSnapshot.new(
              batch_id: batch.id,
              captured_at:,
              job_ids: batch.job_ids,
              jobs: jobs_for(batch)
            )
          end

          private

          attr_reader :rows, :batch_id, :captured_at

          def jobs_for(batch)
            jobs_by_id = RowIndex.new(rows:).jobs_by_id
            batch.job_ids.map do |job_id|
              JobRow.new(row: jobs_by_id.fetch(job_id) { missing_job(batch, job_id) }).to_job
            end
          end

          def missing_job(batch, job_id)
            raise Workflow::InvalidBatchError, "batch #{batch.id.inspect} member job #{job_id.inspect} is not registered"
          end
        end
      end
    end
  end
end
