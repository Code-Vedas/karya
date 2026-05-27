# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Decodes a persisted workflow history row into a history entry.
        class WorkflowHistoryEntryDecoder
          def initialize(row:, batch_id:)
            @row = row
            @batch_id = batch_id
          end

          def decode
            Workflow::HistoryEntry.new(
              kind: row.fetch(:entry_type).to_sym,
              action: details.fetch('action').to_sym,
              occurred_at: row.fetch(:occurred_at),
              workflow_id: details.fetch('workflow_id'),
              workflow_family: details.fetch('workflow_family'),
              workflow_version: details.fetch('workflow_version'),
              batch_id:,
              step_id: details['step_id'],
              job_id: details['job_id'],
              child_batch_id: details['child_batch_id'],
              details: details.fetch('details')
            )
          end

          private

          attr_reader :row, :batch_id

          def details
            @details ||= PayloadCodec.decode(row.fetch(:details_payload))
          end
        end
      end
    end
  end
end
