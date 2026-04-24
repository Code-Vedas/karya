# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Immutable inspection view of one parent-child workflow relationship.
    class ChildWorkflowSnapshot
      WORKFLOW_STATES = %i[pending running blocked succeeded failed cancelled].freeze

      attr_reader :child_batch_id,
                  :child_state,
                  :child_workflow_id,
                  :parent_batch_id,
                  :parent_job_id,
                  :parent_step_id,
                  :parent_workflow_id

      def initialize(**attributes)
        attributes = Attributes.new(attributes)
        @parent_workflow_id = attributes.parent_workflow_id
        @parent_batch_id = attributes.parent_batch_id
        @parent_step_id = attributes.parent_step_id
        @parent_job_id = attributes.parent_job_id
        @child_workflow_id = attributes.child_workflow_id
        @child_batch_id = attributes.child_batch_id
        @child_state = attributes.child_state
        freeze
      end

      # Validates and exposes child workflow relationship attributes.
      class Attributes
        REQUIRED_ATTRIBUTES = %i[
          parent_workflow_id
          parent_batch_id
          parent_step_id
          parent_job_id
          child_workflow_id
          child_batch_id
          child_state
        ].freeze

        def initialize(attributes)
          @attributes = attributes
          validate_keys
        end

        def parent_workflow_id
          Workflow.send(:normalize_identifier, :parent_workflow_id, fetch(:parent_workflow_id))
        end

        def parent_batch_id
          Workflow.send(:normalize_batch_identifier, :parent_batch_id, fetch(:parent_batch_id))
        end

        def parent_step_id
          Workflow.send(:normalize_execution_identifier, :parent_step_id, fetch(:parent_step_id))
        end

        def parent_job_id
          Workflow.send(:normalize_execution_identifier, :parent_job_id, fetch(:parent_job_id))
        end

        def child_workflow_id
          Workflow.send(:normalize_identifier, :child_workflow_id, fetch(:child_workflow_id))
        end

        def child_batch_id
          Workflow.send(:normalize_batch_identifier, :child_batch_id, fetch(:child_batch_id))
        end

        def child_state
          state = fetch(:child_state)
          return state if WORKFLOW_STATES.include?(state)

          raise InvalidExecutionError, 'child_state must be a workflow state'
        end

        private

        attr_reader :attributes

        def fetch(name)
          attributes.fetch(name) { raise ArgumentError, "missing keyword: :#{name}" }
        end

        def validate_keys
          unknown_keys = attributes.keys - REQUIRED_ATTRIBUTES
          return if unknown_keys.empty?

          raise ArgumentError, "unknown keyword: :#{unknown_keys.first}"
        end
      end

      private_constant :Attributes, :WORKFLOW_STATES
    end
  end
end
