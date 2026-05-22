# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'workflow_registration_builder'

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds and validates the durable child-workflow enqueue request context.
        class ChildWorkflowRequestBuilder
          def initialize(operation:, context:)
            @operation = operation
            @context = context
          end

          def build
            definition = workflow_definition_from_request
            now, parent_batch_id, parent_step_id = normalized_identifiers
            rows = context.rows.merge(namespace: context.namespace)
            _parent_batch, parent_registration, = operation.send(:workflow_target, parent_batch_id, rows, now)
            validate_parent_child_step(rows, parent_batch_id, parent_step_id, parent_registration, definition)
            binding = validated_child_workflow_binding(rows, parent_batch_id, definition)
            queued_jobs = operation.send(:validate_workflow_enqueue_jobs, rows, binding.jobs, now)
            registration = WorkflowRegistrationBuilder.new(
              operation:,
              definition:,
              binding:,
              queued_jobs:
            ).build
            parent = ChildWorkflowParentContext.new(
              batch_id: parent_batch_id,
              step_id: parent_step_id,
              registration: parent_registration,
              job_id: parent_registration.step_job_ids.fetch(parent_step_id)
            )

            ChildWorkflowRequest.new(
              now:,
              rows:,
              workflow: ChildWorkflowPayload.new(
                definition:,
                binding:,
                queued_jobs:,
                registration:
              ),
              parent:
            )
          end

          private

          attr_reader :operation, :context

          def workflow_definition_from_request
            definition = operation.request.fetch(:definition)
            raise Workflow::InvalidExecutionError, 'definition must be a Karya::Workflow::Definition' unless definition.is_a?(Workflow::Definition)

            definition
          end

          def normalized_identifiers
            request = operation.request
            now = operation.send(:normalized_workflow_now)
            parent_batch_id = Workflow.send(:normalize_batch_identifier, :parent_batch_id, request.fetch(:parent_batch_id))
            parent_step_id = Workflow.send(:normalize_execution_identifier, :parent_step_id, request.fetch(:parent_step_id))
            [now, parent_batch_id, parent_step_id]
          end

          def validate_parent_child_step(rows, parent_batch_id, parent_step_id, parent_registration, definition)
            step_id = parent_step_id.inspect
            definition_id = definition.id
            expected_child_workflow_id = parent_registration.child_workflow_ids_by_step_id[parent_step_id]
            raise Workflow::InvalidExecutionError, "workflow step #{step_id} is not a child workflow step" unless expected_child_workflow_id
            unless expected_child_workflow_id == definition_id
              raise Workflow::InvalidExecutionError, "child workflow #{definition_id.inspect} does not match parent step #{step_id}"
            end
            if operation.send(:child_relationship_for_parent_step, rows, parent_batch_id, parent_step_id)
              raise Workflow::InvalidExecutionError, "child workflow already registered for step #{step_id}"
            end

            parent_job_id = parent_registration.step_job_ids.fetch(parent_step_id)
            parent_job = Operations::JobRow.new(row: Operations::RowIndex.new(rows:).jobs_by_id.fetch(parent_job_id)).to_job
            raise Workflow::InvalidExecutionError, "parent child workflow step #{step_id} must be queued" unless parent_job.state == :queued
          end

          def validated_child_workflow_binding(rows, parent_batch_id, definition)
            binding = operation.send(:workflow_binding_for, definition)
            batch_id = binding.batch_id
            raise Workflow::InvalidExecutionError, 'child workflow batch id must differ from parent batch id' if batch_id == parent_batch_id
            raise Workflow::DuplicateBatchError, "batch #{batch_id.inspect} already exists" if operation.send(:workflow_batch_row, rows, batch_id)

            binding
          end
        end

        # Captures the durable parent step targeted by one child workflow enqueue.
        class ChildWorkflowParentContext
          def initialize(batch_id:, step_id:, registration:, job_id:)
            @batch_id = batch_id
            @step_id = step_id
            @registration = registration
            @job_id = job_id
          end

          attr_reader :batch_id, :step_id, :registration, :job_id

          def relationship_payload
            {
              parent_workflow_id: registration.workflow_id,
              parent_workflow_family: registration.workflow_family,
              parent_workflow_version: registration.workflow_version,
              parent_batch_id: batch_id,
              parent_job_id: job_id
            }.freeze
          end
        end

        # Carries validated child-workflow enqueue inputs for durable inserts.
        class ChildWorkflowPayload
          def initialize(definition:, binding:, queued_jobs:, registration:)
            @definition = definition
            @binding = binding
            @queued_jobs = queued_jobs
            @registration = registration
          end

          attr_reader :definition, :binding, :queued_jobs, :registration
        end

        # Carries validated child-workflow enqueue inputs for durable inserts.
        class ChildWorkflowRequest
          def initialize(now:, rows:, workflow:, parent:)
            @now = now
            @rows = rows
            @workflow = workflow
            @parent = parent
          end

          attr_reader :now, :rows, :workflow, :parent

          def definition
            workflow.definition
          end

          def binding
            workflow.binding
          end

          def queued_jobs
            workflow.queued_jobs
          end

          def registration
            workflow.registration
          end
        end
      end
    end
  end
end
