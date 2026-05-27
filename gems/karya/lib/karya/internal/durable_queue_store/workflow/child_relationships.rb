# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'child_relationship_policy_row'
require_relative 'child_workflow_snapshot_context'
require_relative 'child_workflow_snapshot_builder'

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Resolves durable parent/child workflow relationships.
        class WorkflowChildRelationships
          def initialize(host:, rows:)
            @host = host
            @rows = rows
          end

          def parent_snapshot(batch_id:, now:, cache:, visiting:)
            relationship = for_child_batch(batch_id)
            return nil unless relationship

            snapshot_builder(relationship:, now:, cache:, visiting:).build
          end

          def snapshots_for_parent_batch(batch_id:, now:, cache:, visiting:)
            for_parent_batch(batch_id).map do |relationship|
              snapshot_builder(relationship:, now:, cache:, visiting:).build
            end.freeze
          end

          def for_parent_batch(parent_batch_id)
            relationship_policy_rows('parent_step', parent_batch_id).map(&:to_relationship)
          end

          def for_parent_job(parent_job_id)
            find_relationship(scope_kind: 'parent_job', scope_value: parent_job_id)
          end

          def for_parent_step(parent_batch_id, parent_step_id)
            find_relationship(scope_kind: 'parent_step', scope_value: "#{parent_batch_id}:#{parent_step_id}")
          end

          def for_child_batch(child_batch_id)
            find_relationship(scope_kind: 'child_batch', scope_value: child_batch_id)
          end

          private

          attr_reader :host, :rows

          def snapshot_builder(relationship:, now:, cache:, visiting:)
            ChildWorkflowSnapshotBuilder.new(
              snapshot_context: ChildWorkflowSnapshotContext.new(host:, rows:, now:, cache:, visiting:),
              relationship:
            )
          end

          def find_relationship(scope_kind:, scope_value:)
            row = policy_rows.find { |candidate| candidate.matches?(scope_kind:, scope_value:) }
            row&.to_relationship
          end

          def relationship_policy_rows(scope_kind, parent_batch_id)
            return policy_rows.select { |candidate| candidate.parent_scope?(parent_batch_id) } if scope_kind == 'parent_step'

            []
          end

          def policy_rows
            @policy_rows ||= rows.fetch(:policy_state, []).map { |row| ChildRelationshipPolicyRow.new(row:) }
          end
        end
      end
    end
  end
end
