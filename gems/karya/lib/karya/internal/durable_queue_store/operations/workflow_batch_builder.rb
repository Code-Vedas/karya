# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Reconstructs the public workflow batch view from durable workflow rows.
        class WorkflowBatchBuilder
          def initialize(rows:, batch_id:)
            @rows = rows
            @batch_id = batch_id
          end

          attr_reader :rows, :batch_id

          def build
            raise Workflow::UnknownBatchError, "batch #{batch_id.inspect} is not registered" unless batch_row

            Workflow::Batch.new(
              id: batch_id,
              job_ids: rows.fetch(:workflow_steps).sort_by { |row| row.fetch(:step_sequence) }.map { |row| row.fetch(:job_id) },
              created_at: batch_row.fetch(:created_at),
              updated_at: batch_row.fetch(:updated_at)
            )
          end

          private

          def batch_row
            @batch_row ||= rows.fetch(:workflow_batches).first
          end
        end
      end
    end
  end
end
