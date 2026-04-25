# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Owner-local child workflow enqueue and lifecycle sync support.
        module ChildWorkflowSupport
          def enqueue_child_workflow(
            parent_batch_id:,
            parent_step_id:,
            definition:,
            jobs_by_step_id:,
            batch_id:,
            now:,
            compensation_jobs_by_step_id: {}
          )
            request = ChildWorkflowRequest.new(
              parent_batch_id: Workflow.send(:normalize_batch_identifier, :parent_batch_id, parent_batch_id),
              parent_step_id: Workflow.send(:normalize_execution_identifier, :parent_step_id, parent_step_id),
              now: normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)
            )

            @mutex.synchronize do
              parent_batch_id = request.parent_batch_id
              parent_step_id = request.parent_step_id
              parent = prepare_child_workflow_parent(parent_batch_id:, parent_step_id:, definition:)
              binding = Workflow.send(:build_compensated_execution_binding, definition:, jobs_by_step_id:, batch_id:, compensation_jobs_by_step_id:)
              validate_child_batch_identity(parent_batch_id:, child_batch_id: binding.batch_id)
              enqueue_child_workflow_binding(parent:, parent_step_id:, binding:, definition:, now: request.now)
            end
          end

          def sync_child_workflows(parent_batch_id:, now:)
            request = ChildWorkflowSyncRequest.new(
              parent_batch_id: Workflow.send(:normalize_batch_identifier, :parent_batch_id, parent_batch_id),
              now: normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)
            )

            @mutex.synchronize do
              parent_batch_id = request.parent_batch_id
              now = request.now
              fetch_workflow_registration(fetch_batch(parent_batch_id).id)
              relationships = child_relationships_for_parent_batch(parent_batch_id)
              Karya::Internal::BulkMutation::ReportBuilder.new(
                action: :sync_child_workflows,
                job_ids: relationships.map(&:parent_job_id),
                now:
              ).to_report do |job_id, changed_jobs, skipped_jobs|
                sync_child_workflow_job(job_id:, now:, changed_jobs:, skipped_jobs:)
              end
            end
          end

          private

          # Normalized child workflow enqueue request.
          class ChildWorkflowRequest
            attr_reader :now, :parent_batch_id, :parent_step_id

            def initialize(parent_batch_id:, parent_step_id:, now:)
              @now = now
              @parent_batch_id = parent_batch_id
              @parent_step_id = parent_step_id
            end
          end

          # Normalized child workflow sync request.
          class ChildWorkflowSyncRequest
            attr_reader :now, :parent_batch_id

            def initialize(parent_batch_id:, now:)
              @now = now
              @parent_batch_id = parent_batch_id
            end
          end

          # Groups the parent-side child workflow step identity.
          ParentChildWorkflow = Struct.new(:parent_workflow_id, :parent_batch_id, :parent_job_id)

          # Builds step-to-job metadata in definition order for child enqueues.
          class ChildStepJobIds
            def initialize(definition:, jobs:)
              @definition = definition
              @jobs = jobs
            end

            def to_h
              definition.steps.each_with_object({}).with_index do |(workflow_step, step_jobs), index|
                step_jobs[workflow_step.id] = jobs.fetch(index).id
              end.freeze
            end

            private

            attr_reader :definition, :jobs
          end

          private_constant :ChildStepJobIds,
                           :ChildWorkflowRequest,
                           :ChildWorkflowSyncRequest,
                           :ParentChildWorkflow

          def enqueue_child_workflow_binding(parent:, parent_step_id:, binding:, definition:, now:)
            jobs = binding.jobs
            batch = build_enqueue_batch(batch_id: binding.batch_id, jobs:, now:)
            validate_bulk_enqueue_uniqueness(jobs, now)
            expire_reservations_locked(now)
            queued_jobs = jobs.map { |job| enqueue_validated_job(job, now) }
            store_batch(batch)
            state.register_workflow_dependencies(binding.dependency_job_ids_by_job_id)
            ChildWorkflowMetadata.new(state:, parent:, parent_step_id:, binding:, definition:).register
            ChildWorkflowReport.new(binding:, queued_jobs:, now:).to_report
          end

          # Registers child workflow metadata after enqueue validation succeeds.
          class ChildWorkflowMetadata
            def initialize(state:, parent:, parent_step_id:, binding:, definition:)
              @state = state
              @parent = parent
              @parent_step_id = parent_step_id
              @binding = binding
              @definition = definition
            end

            def register
              batch_id = binding.batch_id
              workflow_id = definition.id
              state.register_workflow(
                batch_id:,
                workflow_id:,
                step_job_ids: ChildStepJobIds.new(definition:, jobs: binding.jobs).to_h,
                dependency_job_ids_by_job_id: binding.dependency_job_ids_by_job_id,
                compensation_jobs_by_step_id: binding.compensation_jobs_by_step_id,
                child_workflow_ids_by_step_id: WorkflowChildIds.new(definition).to_h
              )
              state.workflow_children.register(
                parent_workflow_id: parent.parent_workflow_id,
                parent_batch_id: parent.parent_batch_id,
                parent_step_id:,
                parent_job_id: parent.parent_job_id,
                child_workflow_id: workflow_id,
                child_batch_id: batch_id
              )
            end

            private

            attr_reader :binding, :definition, :parent, :parent_step_id, :state
          end

          # Builds the public child workflow enqueue report.
          class ChildWorkflowReport
            def initialize(binding:, queued_jobs:, now:)
              @binding = binding
              @queued_jobs = queued_jobs
              @now = now
            end

            def to_report
              BulkMutationReport.new(
                action: :enqueue_child_workflow,
                performed_at: now,
                requested_job_ids: binding.jobs.map(&:id),
                changed_jobs: queued_jobs,
                skipped_jobs: []
              )
            end

            private

            attr_reader :binding, :now, :queued_jobs
          end

          private_constant :ChildWorkflowMetadata, :ChildWorkflowReport

          def prepare_child_workflow_parent(parent_batch_id:, parent_step_id:, definition:)
            parent_batch = fetch_batch(parent_batch_id)
            batch_id = parent_batch.id
            parent_registration = fetch_workflow_registration(batch_id)
            expected_child_workflow_id = parent_registration.child_workflow_ids_by_step_id[parent_step_id]
            validate_child_workflow_parent_step(parent_step_id, expected_child_workflow_id)
            validate_child_workflow_definition(definition, expected_child_workflow_id, parent_step_id)
            validate_child_workflow_not_registered(batch_id, parent_step_id)
            validate_child_workflow_parent_job(parent_registration, parent_step_id, batch_id)
          end

          def validate_child_workflow_parent_step(parent_step_id, expected_child_workflow_id)
            return if expected_child_workflow_id

            raise Workflow::InvalidExecutionError, "workflow step #{parent_step_id.inspect} is not a child workflow step"
          end

          def validate_child_workflow_definition(definition, expected_child_workflow_id, parent_step_id)
            raise Workflow::InvalidExecutionError, 'definition must be a Karya::Workflow::Definition' unless definition.is_a?(Workflow::Definition)

            workflow_id = definition.id
            return if expected_child_workflow_id == workflow_id

            raise Workflow::InvalidExecutionError, "child workflow #{workflow_id.inspect} does not match parent step #{parent_step_id.inspect}"
          end

          def validate_child_workflow_not_registered(parent_batch_id, parent_step_id)
            return unless child_relationship(parent_batch_id, parent_step_id)

            raise Workflow::InvalidExecutionError, "child workflow already registered for step #{parent_step_id.inspect}"
          end

          def validate_child_workflow_parent_job(parent_registration, parent_step_id, parent_batch_id)
            parent_job_id = parent_registration.step_job_ids.fetch(parent_step_id)
            parent_job = state.jobs_by_id.fetch(parent_job_id)
            raise Workflow::InvalidExecutionError, "parent child workflow step #{parent_step_id.inspect} must be queued" unless parent_job.state == :queued

            ParentChildWorkflow.new(parent_registration.workflow_id, parent_batch_id, parent_job_id).freeze
          end

          def validate_child_batch_identity(parent_batch_id:, child_batch_id:)
            return unless parent_batch_id == child_batch_id

            raise Workflow::InvalidExecutionError, 'child workflow batch id must differ from parent batch id'
          end

          def child_relationship(parent_batch_id, parent_step_id)
            state.workflow_children.for_parent_step(parent_batch_id, parent_step_id)
          end

          def child_relationships_for_parent_batch(parent_batch_id)
            state.workflow_children.for_parent_batch(parent_batch_id)
          end

          def sync_child_workflow_job(job_id:, now:, changed_jobs:, skipped_jobs:)
            relationship = state.workflow_children.for_parent_job(job_id)
            child_batch_id = relationship.child_batch_id
            case child_workflow_state(child_batch_id)
            when :failed
              dead_letter_requested_job(job_id, now, "child workflow #{child_batch_id} failed", changed_jobs, skipped_jobs)
            when :cancelled
              cancel_requested_job(job_id, now, changed_jobs, skipped_jobs)
            else
              parent_job = state.jobs_by_id.fetch(job_id)
              skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :ineligible_state, state: parent_job.state).to_h
            end
          end

          def child_workflow_state(child_batch_id)
            batch_id = fetch_batch(child_batch_id).id
            WorkflowChildState.new(state:, now: Time.at(0)).resolve(batch_id)
          end
        end
      end
    end
  end
end
