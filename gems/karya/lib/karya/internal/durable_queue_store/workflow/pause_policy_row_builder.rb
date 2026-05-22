# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Builds the durable workflow pause policy row.
        class PausePolicyRowBuilder
          def initialize(namespace:, batch_id:, now:)
            @namespace = namespace
            @batch_id = batch_id
            @now = now
          end

          def build
            PolicyRowBuilder.new(
              context: PolicyRowContext.new(
                namespace:,
                policy_kind: 'workflow_pause',
                scope: { kind: 'workflow', value: batch_id },
                state_payload: { requested_at: now },
                updated_at: now
              )
            ).build
          end

          private

          attr_reader :namespace, :batch_id, :now
        end
      end
    end
  end
end
