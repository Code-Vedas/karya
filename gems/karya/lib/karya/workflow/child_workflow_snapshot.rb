# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Immutable inspection view of one parent-child workflow relationship.
    class ChildWorkflowSnapshot
      WORKFLOW_STATES = %i[pending running paused awaiting_approval blocked succeeded failed cancelled].freeze
      attr_reader :child_state

      def initialize(**attributes)
        attributes = Attributes.new(attributes)
        @parent = attributes.parent_identity
        @child = attributes.child_identity
        @child_state = attributes.child_state
        freeze
      end

      def parent_workflow_id = parent.workflow_id

      def parent_workflow_family = parent.workflow_family

      def parent_workflow_version = parent.workflow_version

      def parent_batch_id = parent.batch_id

      def parent_step_id = parent.step_id

      def parent_job_id = parent.job_id

      def child_workflow_id = child.workflow_id

      def child_workflow_family = child.workflow_family

      def child_workflow_version = child.workflow_version

      def child_batch_id = child.batch_id

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
        OPTIONAL_ATTRIBUTES = %i[
          parent_workflow_family
          parent_workflow_version
          child_workflow_family
          child_workflow_version
        ].freeze
        SUPPORTED_ATTRIBUTES = (REQUIRED_ATTRIBUTES + OPTIONAL_ATTRIBUTES).freeze

        def initialize(attributes)
          @attributes = attributes
          validate_keys
        end

        def parent_workflow_id
          Workflow.send(:normalize_identifier, :parent_workflow_id, fetch(:parent_workflow_id))
        end

        def parent_workflow_family
          value = attributes.fetch(:parent_workflow_family, parent_workflow_id)
          Workflow.send(:normalize_identifier, :parent_workflow_family, value)
        end

        def parent_workflow_version
          value = attributes.fetch(:parent_workflow_version, 'v1')
          Workflow.send(:normalize_identifier, :parent_workflow_version, value)
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

        def child_workflow_family
          value = attributes.fetch(:child_workflow_family, child_workflow_id)
          Workflow.send(:normalize_identifier, :child_workflow_family, value)
        end

        def child_workflow_version
          value = attributes.fetch(:child_workflow_version, 'v1')
          Workflow.send(:normalize_identifier, :child_workflow_version, value)
        end

        def child_batch_id
          Workflow.send(:normalize_batch_identifier, :child_batch_id, fetch(:child_batch_id))
        end

        def child_state
          state = fetch(:child_state)
          return state if WORKFLOW_STATES.include?(state)

          raise InvalidExecutionError, 'child_state must be a workflow state'
        end

        def parent_identity
          ParentIdentity.new(
            workflow_id: parent_workflow_id,
            workflow_family: parent_workflow_family,
            workflow_version: parent_workflow_version,
            batch_id: parent_batch_id,
            step_id: parent_step_id,
            job_id: parent_job_id
          )
        end

        def child_identity
          ChildIdentity.new(
            workflow_id: child_workflow_id,
            workflow_family: child_workflow_family,
            workflow_version: child_workflow_version,
            batch_id: child_batch_id
          )
        end

        private

        attr_reader :attributes

        def fetch(name)
          attributes.fetch(name) { raise ArgumentError, "missing keyword: :#{name}" }
        end

        def validate_keys
          unknown_keys = attributes.keys - SUPPORTED_ATTRIBUTES
          return if unknown_keys.empty?

          raise ArgumentError, "unknown keyword: :#{unknown_keys.first}"
        end
      end

      # Immutable parent-side workflow identity for one child relationship.
      class ParentIdentity
        attr_reader :batch_id, :job_id, :step_id, :workflow_family, :workflow_id, :workflow_version

        def initialize(attributes)
          @workflow_id = attributes.fetch(:workflow_id)
          @workflow_family = attributes.fetch(:workflow_family)
          @workflow_version = attributes.fetch(:workflow_version)
          @batch_id = attributes.fetch(:batch_id)
          @step_id = attributes.fetch(:step_id)
          @job_id = attributes.fetch(:job_id)
          freeze
        end
      end

      # Immutable child-side workflow identity for one child relationship.
      class ChildIdentity
        attr_reader :batch_id, :workflow_family, :workflow_id, :workflow_version

        def initialize(attributes)
          @workflow_id = attributes.fetch(:workflow_id)
          @workflow_family = attributes.fetch(:workflow_family)
          @workflow_version = attributes.fetch(:workflow_version)
          @batch_id = attributes.fetch(:batch_id)
          freeze
        end
      end

      private

      attr_reader :child, :parent

      private_constant :Attributes, :ChildIdentity, :ParentIdentity, :WORKFLOW_STATES
    end
  end
end
