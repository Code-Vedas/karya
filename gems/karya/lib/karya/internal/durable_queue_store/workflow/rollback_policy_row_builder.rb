# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Builds the durable rollback policy row for a workflow batch.
        class RollbackPolicyRowBuilder
          # Immutable inputs for building one workflow rollback policy row.
          Request = Struct.new(
            :namespace,
            :batch_id,
            :rollback_batch_id,
            :reason,
            :requested_at,
            :compensation_job_ids,
            keyword_init: true
          )

          def initialize(request:)
            @request = request
          end

          def build
            PolicyRowBuilder.new(
              context: PolicyRowContext.new(
                namespace:,
                policy_kind: 'workflow_rollback',
                scope: { kind: 'workflow', value: batch_id },
                state_payload: payload,
                updated_at: requested_at
              )
            ).build
          end

          private

          attr_reader :request

          def namespace = request.namespace
          def batch_id = request.batch_id
          def rollback_batch_id = request.rollback_batch_id
          def reason = request.reason
          def requested_at = request.requested_at
          def compensation_job_ids = request.compensation_job_ids

          def payload
            {
              batch_id:,
              rollback_batch_id:,
              reason:,
              requested_at:,
              compensation_job_ids:
            }
          end
        end
      end
    end
  end
end
