# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Builds the durable approval-decision policy row for one workflow checkpoint job.
        class ApprovalPolicyRowBuilder
          def initialize(namespace:, job_id:, state:, decided_at:, reason: nil)
            @namespace = namespace
            @job_id = job_id
            @state = state
            @decided_at = decided_at
            @reason = reason
          end

          def build
            PolicyRowBuilder.new(
              context: PolicyRowContext.new(
                namespace:,
                policy_kind: 'workflow_approval_decision',
                scope: { kind: 'job', value: job_id },
                state_payload: payload,
                updated_at: decided_at
              )
            ).build
          end

          private

          attr_reader :namespace, :job_id, :state, :decided_at, :reason

          def payload
            { state:, decided_at: }.tap do |value|
              value[:reason] = reason if reason
            end
          end
        end
      end
    end
  end
end
