# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'history_entry_decoder'
require_relative 'interaction_snapshot_decoder'

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Builds workflow history and interaction snapshots from durable rows.
        class WorkflowHistoryBuilder
          def initialize(host:, rows:)
            @host = host
            @rows = rows
          end

          def snapshot(batch_id:, now:)
            registration = host.send(:registration_for_batch, rows, batch_id)
            Workflow::HistorySnapshot.new(
              workflow_id: registration.workflow_id,
              workflow_family: registration.workflow_family,
              workflow_version: registration.workflow_version,
              batch_id:,
              captured_at: now,
              entries: entries(batch_id)
            )
          end

          def entries(batch_id)
            group_rows(:workflow_history, batch_id).map do |row|
              WorkflowHistoryEntryDecoder.new(row:, batch_id:).decode
            end.freeze
          end

          def interactions(batch_id)
            group_rows(:workflow_interactions, batch_id).map { |row| WorkflowInteractionSnapshotDecoder.new(row:).decode }.freeze
          end

          def history_row(namespace:, batch_id:, entry:)
            WorkflowHistoryRecord.new(
              namespace:,
              batch_id:,
              sequence: next_sequence(:workflow_history, batch_id),
              entry:
            ).to_h
          end

          def interaction_row(namespace:, batch_id:, interaction:)
            WorkflowInteractionRecord.new(
              namespace:,
              batch_id:,
              sequence: next_sequence(:workflow_interactions, batch_id),
              interaction:
            ).to_h
          end

          private

          attr_reader :host, :rows

          def group_rows(group_name, batch_id)
            rows.fetch(group_name)
                .select { |row| workflow_batch_row?(row, batch_id) }
                .sort_by { |row| workflow_sequence(row) }
          end

          def next_sequence(group_name, batch_id)
            group_rows(group_name, batch_id).map { |row| workflow_sequence(row) }.max.to_i + 1
          end

          def workflow_batch_row?(row, batch_id)
            row.fetch(:batch_id) == batch_id
          end

          def workflow_sequence(row)
            row.fetch(:sequence)
          end
        end
      end
    end
  end
end
