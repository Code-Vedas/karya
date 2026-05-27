# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Builds one durable workflow-history row from an immutable history entry.
      class WorkflowHistoryRecord
        def initialize(namespace:, batch_id:, sequence:, entry:)
          @namespace = namespace
          @batch_id = batch_id
          @sequence = sequence
          @entry = entry
        end

        def to_h
          {
            namespace:,
            batch_id:,
            sequence:,
            entry_type: entry.kind.to_s,
            details_payload: PayloadCodec.dump(history_details),
            occurred_at: entry.occurred_at
          }
        end

        private

        attr_reader :batch_id, :entry, :namespace, :sequence

        def history_details
          {
            'action' => entry.action.to_s,
            'workflow_id' => entry.workflow_id,
            'workflow_family' => entry.workflow_family,
            'workflow_version' => entry.workflow_version,
            'step_id' => entry.step_id,
            'job_id' => entry.job_id,
            'child_batch_id' => entry.child_batch_id,
            'details' => entry.details
          }.freeze
        end
      end
    end
  end
end
