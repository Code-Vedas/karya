# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Decodes a persisted workflow interaction row into a snapshot.
        class WorkflowInteractionSnapshotDecoder
          def initialize(row:)
            @row = row
          end

          def decode
            Workflow::InteractionSnapshot.new(
              kind: row.fetch(:kind),
              name: row.fetch(:name),
              payload: PayloadCodec.decode(row.fetch(:payload)),
              received_at: row.fetch(:received_at)
            )
          end

          private

          attr_reader :row
        end
      end
    end
  end
end
