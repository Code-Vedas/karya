# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Builds the three durable policy rows that link a parent workflow step/job to a child batch.
        class ChildRelationshipPolicyRowsBuilder
          # Immutable inputs for building child-relationship policy rows.
          Request = Struct.new(
            :namespace,
            :parent,
            :parent_step_id,
            :definition,
            :child_batch_id,
            :now,
            keyword_init: true
          )

          def initialize(request:)
            @request = request
          end

          def build
            scopes.map do |scope|
              PolicyRowBuilder.new(
                context: PolicyRowContext.new(
                  namespace:,
                  policy_kind: 'workflow_child_relationship',
                  scope:,
                  state_payload: payload,
                  updated_at: now
                )
              ).build
            end.freeze
          end

          private

          attr_reader :request

          def namespace = request.namespace
          def parent = request.parent
          def parent_step_id = request.parent_step_id
          def definition = request.definition
          def child_batch_id = request.child_batch_id
          def now = request.now

          def payload
            {
              parent_workflow_id: parent.fetch(:parent_workflow_id),
              parent_workflow_family: parent.fetch(:parent_workflow_family),
              parent_workflow_version: parent.fetch(:parent_workflow_version),
              parent_batch_id: parent.fetch(:parent_batch_id),
              parent_step_id:,
              parent_job_id: parent.fetch(:parent_job_id),
              child_workflow_id: definition.id,
              child_workflow_family: definition.workflow_family,
              child_workflow_version: definition.workflow_version,
              child_batch_id:
            }
          end

          def scopes
            [
              { kind: 'parent_step', value: "#{parent.fetch(:parent_batch_id)}:#{parent_step_id}" },
              { kind: 'parent_job', value: parent.fetch(:parent_job_id) },
              { kind: 'child_batch', value: child_batch_id }
            ]
          end
        end
      end
    end
  end
end
