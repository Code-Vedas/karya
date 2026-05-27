# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Shared immutable inputs for durable workflow policy-row builders.
        PolicyRowContext = Struct.new(
          :namespace,
          :policy_kind,
          :scope,
          :state_payload,
          :updated_at,
          keyword_init: true
        )
      end
    end
  end
end
