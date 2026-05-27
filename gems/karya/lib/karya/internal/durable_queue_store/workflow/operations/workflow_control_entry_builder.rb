# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds workflow control history entries from registration state.
        class WorkflowControlEntryBuilder
          def initialize(registration:, batch_id:, occurred_at:, entry: {})
            @registration = registration
            @batch_id = batch_id
            @occurred_at = occurred_at
            @entry = entry
          end

          def build
            Workflow::HistoryEntry.new(
              kind: entry.fetch(:kind),
              action: entry.fetch(:action),
              occurred_at:,
              workflow_id: registration.workflow_id,
              workflow_family: registration.workflow_family,
              workflow_version: registration.workflow_version,
              batch_id:,
              step_id: entry[:step_id],
              job_id: entry[:job_id],
              child_batch_id: entry[:child_batch_id],
              details: entry.fetch(:details, {})
            )
          end

          private

          attr_reader :registration, :batch_id, :occurred_at, :entry
        end
      end
    end
  end
end
