# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    module Internal
      module ReferenceQueueStore
        module Internal
          # Owner-local workflow enqueue and snapshot helper types.
          module WorkflowSupport
            # Builds the stored registration payload for one workflow enqueue.
            class WorkflowRegistrationPayload
              def initialize(definition:, binding:, workflow_batch_id:, step_job_ids:, dependency_job_ids_by_job_id:)
                @definition = definition
                @binding = binding
                @workflow_batch_id = workflow_batch_id
                @step_job_ids = step_job_ids
                @dependency_job_ids_by_job_id = dependency_job_ids_by_job_id
              end

              def to_h
                {
                  batch_id: workflow_batch_id,
                  workflow_id: definition.id,
                  workflow_family: definition.workflow_family,
                  workflow_version: definition.workflow_version,
                  step_job_ids:,
                  dependency_job_ids_by_job_id:,
                  approval_requirements_by_job_id: ApprovalRequirements.new(definition:, step_job_ids:).to_h,
                  interaction_requirements_by_job_id: InteractionRequirements.new(definition:, step_job_ids:).to_h,
                  compensation_jobs_by_step_id: binding.compensation_jobs_by_step_id,
                  child_workflow_ids_by_step_id: WorkflowChildIds.new(definition).to_h
                }
              end

              private

              attr_reader :binding, :definition, :dependency_job_ids_by_job_id, :step_job_ids, :workflow_batch_id
            end

            # Groups the validated rollback batch and enqueue plan.
            Rollback = Struct.new(:workflow_batch_id, :rollback_batch_id, :batch, :plan)

            # Builds a deterministic rollback batch id for one workflow batch.
            class RollbackBatchId
              PREFIX = '__karya_workflow_rollback_v1__'
              private_constant :PREFIX

              def initialize(batch_id)
                @batch_id = batch_id
              end

              def to_s
                "#{PREFIX}#{batch_id.unpack1('H*')}".freeze
              end

              private

              attr_reader :batch_id
            end

            # Immutable rollback enqueue plan.
            class RollbackPlan
              # Immutable compensation jobs and dependency metadata.
              Plan = Struct.new(:jobs, :dependency_job_ids_by_job_id)
              private_constant :Plan

              def initialize(registration:, jobs:)
                @registration = registration
                @jobs_by_id = jobs.to_h { |job| [job.id, job] }
              end

              def to_plan
                compensation_jobs = ordered_compensation_jobs
                Plan.new(compensation_jobs.freeze, RollbackDependencies.new(compensation_jobs).to_h).freeze
              end

              private

              attr_reader :jobs_by_id, :registration

              def ordered_compensation_jobs
                step_job_ids = registration.step_job_ids
                step_job_ids.keys.reverse.filter_map do |step_id|
                  primary_job = jobs_by_id.fetch(step_job_ids.fetch(step_id))
                  next unless primary_job.state == :succeeded

                  registration.compensation_jobs_by_step_id[step_id]
                end
              end
            end

            # Builds serial dependency metadata for rollback compensation jobs.
            class RollbackDependencies
              def initialize(jobs)
                @jobs = jobs
              end

              def to_h
                previous_job_id = nil
                jobs.each_with_object({}) do |job, dependencies|
                  job_id = job.id
                  dependencies[job_id] = previous_job_id ? [previous_job_id].freeze : [].freeze
                  previous_job_id = job_id
                end.freeze
              end

              private

              attr_reader :jobs
            end

            # Builds step-to-job metadata in definition order.
            class StepJobIds
              def initialize(definition:, jobs:)
                @definition = definition
                @jobs = jobs
              end

              def to_h
                definition.steps.each_with_object({}).with_index do |(workflow_step, step_job_ids), index|
                  step_job_ids[workflow_step.id] = jobs.fetch(index).id
                end.freeze
              end

              private

              attr_reader :definition, :jobs
            end

            # Normalizes an explicit workflow step target list for operator controls.
            class WorkflowStepIds
              def initialize(step_ids)
                @step_ids = step_ids
              end

              def to_a
                raise Workflow::InvalidExecutionError, 'step_ids must be an Array' unless step_ids.is_a?(Array)
                raise Workflow::InvalidExecutionError, 'step_ids must not be empty' if step_ids.empty?

                normalize_step_ids
              end

              private

              attr_reader :step_ids

              def normalize_step_ids
                normalized = []
                seen = {}
                step_ids.each do |step_id|
                  normalized_step_id = Workflow.send(:normalize_execution_identifier, :step_id, step_id)
                  raise Workflow::InvalidExecutionError, "duplicate workflow step #{normalized_step_id.inspect}" if seen.key?(normalized_step_id)

                  seen[normalized_step_id] = true
                  normalized << normalized_step_id
                end
                normalized.freeze
              end
            end

            # Resolves explicit workflow step ids to primary workflow job ids.
            class WorkflowControlTargets
              def initialize(registration:, step_ids:)
                @registration = registration
                @step_ids = WorkflowStepIds.new(step_ids).to_a
              end

              def job_ids
                step_ids.map do |step_id|
                  step_job_ids.fetch(step_id) do
                    raise Workflow::InvalidExecutionError, "unknown workflow step #{step_id.inspect}"
                  end
                end.freeze
              end

              private

              attr_reader :registration, :step_ids

              def step_job_ids
                registration.step_job_ids
              end
            end

            # Builds workflow snapshots from stored workflow metadata.
            class WorkflowSnapshotBuilder
              def initialize(batch:, registration:, jobs:, now:, state:)
                @batch = batch
                @registration = registration
                @jobs = jobs
                @now = now
                @state = state
              end

              def to_snapshot
                workflow_batch_id = batch.id
                Workflow::Snapshot.new(
                  workflow_id: registration.workflow_id,
                  workflow_family: registration.workflow_family,
                  workflow_version: registration.workflow_version,
                  batch_id: workflow_batch_id,
                  captured_at: now,
                  step_job_ids: registration.step_job_ids,
                  dependency_job_ids_by_job_id: registration.dependency_job_ids_by_job_id,
                  jobs:,
                  approval_requirements_by_job_id: registration.approval_requirements_by_job_id,
                  approval_decisions_by_job_id: approval_decisions_by_job_id,
                  child_workflow_ids_by_step_id: registration.child_workflow_ids_by_step_id,
                  child_workflows: child_workflow_snapshots,
                  interaction_requirements_by_job_id: registration.interaction_requirements_by_job_id,
                  interaction_received_at_by_job_id: interaction_received_at_by_job_id,
                  interactions: interaction_snapshots,
                  pause_requested_at: state.workflow_pause_requested_at(workflow_batch_id),
                  parent: parent_snapshot,
                  rollback: rollback_snapshot
                )
              end

              private

              attr_reader :batch, :jobs, :now, :registration, :state

              def rollback_snapshot
                rollback = state.workflow_rollbacks_by_batch_id[batch.id]
                return unless rollback

                RollbackSnapshotAttributes.new(rollback.to_h).to_snapshot
              end

              def child_workflow_snapshots
                state.workflow_children.for_parent_batch(batch.id).map do |relationship|
                  ChildWorkflowSnapshotBuilder.new(relationship:, resolver: child_state_resolver).to_snapshot
                end.freeze
              end

              def parent_snapshot
                relationship = state.workflow_children.for_child_batch(batch.id)
                return unless relationship

                ChildWorkflowSnapshotBuilder.new(relationship:, resolver: child_state_resolver).to_snapshot
              end

              def interaction_snapshots
                state.workflow_interactions_for(batch.id)
              end

              def interaction_received_at_by_job_id
                registration.interaction_requirements_by_job_id.each_with_object({}) do |(job_id, requirement), received_at_by_job_id|
                  received_at = state.workflow_interaction_received_at(
                    batch_id: batch.id,
                    kind: requirement.fetch(:kind),
                    name: requirement.fetch(:name)
                  )
                  received_at_by_job_id[job_id] = received_at if received_at
                end.freeze
              end

              def approval_decisions_by_job_id
                registration.approval_requirements_by_job_id.each_with_object({}) do |(job_id, _requirement), decisions|
                  decision = state.workflow_approval_decision_for(job_id)
                  decisions[job_id] = decision.to_snapshot_decision if decision
                end.freeze
              end

              def child_state_resolver
                @child_state_resolver ||= WorkflowChildState.new(state:, now:)
              end
            end

            private_constant :Rollback, :RollbackBatchId, :RollbackDependencies,
                             :RollbackPlan, :StepJobIds, :WorkflowControlTargets,
                             :WorkflowRegistrationPayload, :WorkflowSnapshotBuilder,
                             :WorkflowStepIds
          end
        end
      end
    end
  end
end
