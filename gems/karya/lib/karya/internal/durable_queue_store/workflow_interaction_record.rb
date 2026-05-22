# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Builds one durable workflow-interaction row from an immutable inbox entry.
      class WorkflowInteractionRecord
        def initialize(namespace:, batch_id:, sequence:, interaction:)
          @namespace = namespace
          @batch_id = batch_id
          @sequence = sequence
          @interaction = interaction
        end

        def to_h
          {
            namespace:,
            batch_id:,
            sequence:,
            kind: interaction.kind.to_s,
            name: interaction.name,
            payload: PayloadCodec.dump(interaction.payload),
            received_at: interaction.received_at
          }
        end

        private

        attr_reader :batch_id, :interaction, :namespace, :sequence
      end
    end
  end
end
