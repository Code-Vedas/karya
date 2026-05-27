# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Loads the workflow batch jobs from durable rows for snapshot reconstruction.
        class SnapshotJobLoader
          def initialize(rows:, batch_id:, batch:)
            @rows = rows
            @batch_id = batch_id
            @batch = batch
          end

          def load
            batch.job_ids.map do |job_id|
              job_row = row_index.jobs_by_id.fetch(job_id) do
                raise Workflow::InvalidExecutionError, "batch #{batch_id.inspect} member job #{job_id.inspect} is not registered"
              end
              Operations::JobRow.new(row: job_row).to_job
            end
          end

          private

          attr_reader :rows, :batch_id, :batch

          def row_index
            @row_index ||= Operations::RowIndex.new(rows:)
          end
        end
      end
    end
  end
end
