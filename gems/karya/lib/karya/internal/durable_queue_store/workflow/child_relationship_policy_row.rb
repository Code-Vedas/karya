# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Wraps a policy row that stores a workflow parent/child relationship.
        class ChildRelationshipPolicyRow
          POLICY_KIND = 'workflow_child_relationship'

          def initialize(row:)
            @row = row
          end

          def matches?(scope_kind:, scope_value:)
            relationship? &&
              row.fetch(:scope_kind) == scope_kind &&
              row.fetch(:scope_value) == scope_value
          end

          def parent_scope?(parent_batch_id)
            relationship? &&
              row.fetch(:scope_kind) == 'parent_step' &&
              row.fetch(:scope_value).start_with?("#{parent_batch_id}:")
          end

          def to_relationship
            WorkflowChildRelationship.new(
              parent_workflow_id: payload.fetch('parent_workflow_id'),
              parent_workflow_family: payload.fetch('parent_workflow_family'),
              parent_workflow_version: payload.fetch('parent_workflow_version'),
              parent_batch_id: payload.fetch('parent_batch_id'),
              parent_step_id: payload.fetch('parent_step_id'),
              parent_job_id: payload.fetch('parent_job_id'),
              child_workflow_id: payload.fetch('child_workflow_id'),
              child_workflow_family: payload.fetch('child_workflow_family'),
              child_workflow_version: payload.fetch('child_workflow_version'),
              child_batch_id: payload.fetch('child_batch_id')
            ).freeze
          end

          private

          attr_reader :row

          def relationship?
            row.fetch(:policy_kind) == POLICY_KIND
          end

          def payload
            @payload ||= PayloadCodec.decode(row.fetch(:state_payload))
          end
        end
      end
    end
  end
end
