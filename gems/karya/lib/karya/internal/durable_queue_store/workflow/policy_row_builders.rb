# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'policy_row_context'
require_relative 'policy_row_builder'
require_relative 'child_relationship_policy_rows_builder'
require_relative 'pause_policy_row_builder'
require_relative 'approval_policy_row_builder'
require_relative 'rollback_policy_row_builder'
require_relative 'interaction_support_validator'

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Builds workflow-specific policy rows for pause, approval, rollback, and child links.
        module PolicyRowBuilders
          private

          def build_workflow_child_relationship_rows(namespace:, parent:, parent_step_id:, definition:, child_batch_id:, now:)
            ChildRelationshipPolicyRowsBuilder.new(
              request: ChildRelationshipPolicyRowsBuilder::Request.new(
                namespace:,
                parent:,
                parent_step_id:,
                definition:,
                child_batch_id:,
                now:
              )
            ).build
          end

          def build_workflow_pause_row(namespace:, batch_id:, now:)
            PausePolicyRowBuilder.new(namespace:, batch_id:, now:).build
          end

          def build_workflow_approval_row(namespace:, job_id:, state:, decided_at:, reason: nil)
            ApprovalPolicyRowBuilder.new(
              namespace:,
              job_id:,
              state:,
              decided_at:,
              reason:
            ).build
          end

          def build_workflow_rollback_row(namespace:, batch_id:, rollback_batch_id:, reason:, requested_at:, compensation_job_ids:)
            RollbackPolicyRowBuilder.new(
              request: RollbackPolicyRowBuilder::Request.new(
                namespace:,
                batch_id:,
                rollback_batch_id:,
                reason:,
                requested_at:,
                compensation_job_ids:
              )
            ).build
          end

          def validate_workflow_interaction_support!(registration, interaction_kind, interaction_name, batch_id)
            InteractionSupportValidator.new(
              registration:,
              interaction_kind:,
              interaction_name:,
              batch_id:
            ).validate
          end
        end
      end
    end
  end
end
