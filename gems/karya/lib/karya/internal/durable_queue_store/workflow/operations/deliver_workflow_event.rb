# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Records a durable workflow event and any side effects it triggers.
        class DeliverWorkflowEvent < DeliverWorkflowSignal
          def call(context:)
            deliver(context, kind: :event, action: :deliver_workflow_event)
          end
        end
      end
    end
  end
end
