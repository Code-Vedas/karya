# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds the durable workflow history row for one delivered signal or event.
        class WorkflowInteractionHistoryBuilder
          def initialize(operation:, interaction_request:, kind:)
            @operation = operation
            @interaction_request = interaction_request
            @kind = kind
          end

          def build
            operation.send(
              :workflow_control_row,
              rows: interaction_request.rows,
              namespace: interaction_request.namespace,
              batch_id:,
              entry: WorkflowControlEntryBuilder.new(
                registration: interaction_request.registration,
                batch_id:,
                occurred_at: interaction_request.now,
                entry: { kind: :interaction, action:, details: }
              ).build
            )
          end

          private

          attr_reader :operation, :interaction_request, :kind

          def batch_id
            interaction_request.batch_id
          end

          def action
            kind == :signal ? :signal_delivered : :event_delivered
          end

          def details
            { 'name' => interaction_request.name, 'payload' => interaction_request.interaction.payload }
          end
        end
      end
    end
  end
end
