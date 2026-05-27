# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Persists one workflow control-plane policy row from a normalized context.
        class PolicyRowBuilder
          def initialize(context:)
            @context = context
          end

          def build
            PolicyStateRecord.new(
              namespace: context.namespace,
              policy_kind: context.policy_kind,
              scope: context.scope,
              state_payload: PolicyStateRecord.stringify_payload(context.state_payload),
              updated_at: context.updated_at
            ).to_h
          end

          private

          attr_reader :context
        end
      end
    end
  end
end
