# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'workflow/value_objects'
require_relative 'workflow/registration_builder'
require_relative 'workflow/registration_maps_builder'
require_relative 'workflow/interaction_supported_keys_builder'
require_relative 'workflow/registration_loader'
require_relative 'workflow/policy_context'
require_relative 'workflow/snapshot_builder'
require_relative 'workflow/rollback_support'
require_relative 'workflow/policy_row_builders'
require_relative 'workflow/history_builder'
require_relative 'workflow/row_mutator'
require_relative 'workflow/step_binding_support'
require_relative 'workflow/enqueue_validator'
require_relative 'workflow/child_relationships'
require_relative 'workflow/dependency_gate'

module Karya
  module Internal
    module DurableQueueStore
      # Shared row-native workflow reconstruction and mutation helpers.
      module WorkflowRuntimeSupport
        include RegistrationLoader
        include SnapshotBuilder
        include RollbackSupport
        include PolicyRowBuilders

        private

        def workflow_history_snapshot(rows:, batch_id:, now:)
          workflow_history_builder(rows).snapshot(batch_id:, now:)
        end

        def workflow_history_entries(rows, batch_id)
          workflow_history_builder(rows).entries(batch_id)
        end

        def workflow_interactions(rows, batch_id)
          workflow_history_builder(rows).interactions(batch_id)
        end

        def build_workflow_history_row(rows:, namespace:, batch_id:, entry:)
          workflow_history_builder(rows).history_row(namespace:, batch_id:, entry:)
        end

        def build_workflow_interaction_row(rows:, namespace:, batch_id:, interaction:)
          workflow_history_builder(rows).interaction_row(namespace:, batch_id:, interaction:)
        end

        def workflow_batch_row(rows, batch_id)
          workflow_row_mutator(rows).batch_row(batch_id)
        end

        def workflow_batch_from_rows(rows, batch_id)
          workflow_row_mutator(rows).batch_from_rows(batch_id)
        end

        def workflow_step_rows_for_batch(rows, batch_id)
          workflow_row_mutator(rows).step_rows_for_batch(batch_id)
        end

        def workflow_step_rows_for_job(rows, job_id)
          workflow_row_mutator(rows).step_rows_for_job(job_id)
        end

        def workflow_row_updates_for_job(context, rows, replacement_job)
          workflow_row_mutator(rows).row_updates_for_job(context:, replacement_job:)
        end

        def update_rows_with_workflow_job(rows, job_id, replacement_job)
          workflow_row_mutator(rows).update_rows_with_job(job_id, replacement_job)
        end

        def workflow_history_rows_for_job(rows, namespace:, replacement_job:, from_state: nil)
          workflow_row_mutator(rows).history_rows_for_job(namespace:, replacement_job:, from_state:)
        end

        def workflow_step_id_rows(definition:, step_job_ids:, binding:)
          WorkflowStepBindings.new(definition:, step_job_ids:, binding:).rows
        end

        def workflow_control_job_ids(registration, step_ids)
          WorkflowStepBindings.new(registration:, step_ids:).control_job_ids
        end

        def normalize_workflow_step_ids(step_ids)
          WorkflowStepBindings.new(registration: nil, step_ids:).send(:normalized_step_ids)
        end

        def validate_workflow_enqueue_jobs(rows, jobs, now)
          WorkflowEnqueueValidator.new(rows:, now:).validate(jobs)
        end

        def workflow_dependencies_satisfied?(rows, job, now:)
          WorkflowDependencyEvaluator.new(host: self, rows:, job:, now:).satisfied?
        end

        def workflow_paused?(rows, batch_id)
          !!workflow_pause_requested_at(rows, batch_id)
        end

        def workflow_interaction_satisfied?(rows, registration, batch_id, job)
          WorkflowDependencyEvaluator.new(
            host: self,
            rows:,
            job:,
            now: Time.now,
            target: WorkflowDependencyTarget.new(registration:, batch_id:)
          ).interaction_satisfied?
        end

        def workflow_approval_satisfied?(rows, registration, batch_id, job)
          WorkflowDependencyEvaluator.new(
            host: self,
            rows:,
            job:,
            now: Time.now,
            target: WorkflowDependencyTarget.new(registration:, batch_id:)
          ).approval_satisfied?
        end

        def workflow_child_satisfied?(rows, registration, job, now)
          job_id = job.id
          step_id = registration.step_id_by_job_id.fetch(job_id)
          batch_id = workflow_step_rows_for_job(rows, job_id).find { |row| row.fetch(:step_id) == step_id }&.fetch(:batch_id)
          WorkflowDependencyEvaluator.new(
            host: self,
            rows:,
            job:,
            now:,
            target: WorkflowDependencyTarget.new(registration:, batch_id: batch_id || '')
          ).child_satisfied?
        end

        def workflow_parent_snapshot(rows, batch_id, now, cache:, visiting:)
          workflow_child_relationships(rows).parent_snapshot(batch_id:, now:, cache:, visiting:)
        end

        def child_workflow_snapshots(rows, batch_id, now, cache:, visiting:)
          workflow_child_relationships(rows).snapshots_for_parent_batch(batch_id:, now:, cache:, visiting:)
        end

        def child_relationships_for_parent_batch(rows, parent_batch_id)
          workflow_child_relationships(rows).for_parent_batch(parent_batch_id)
        end

        def child_relationship_for_parent_job(rows, parent_job_id)
          workflow_child_relationships(rows).for_parent_job(parent_job_id)
        end

        def child_relationship_for_parent_step(rows, parent_batch_id, parent_step_id)
          workflow_child_relationships(rows).for_parent_step(parent_batch_id, parent_step_id)
        end

        def child_relationship_for_child_batch(rows, child_batch_id)
          workflow_child_relationships(rows).for_child_batch(child_batch_id)
        end

        def workflow_operation?(operation_name)
          operation_name.to_s.include?('workflow')
        end

        def workflow_pause_requested_at(rows, batch_id)
          workflow_policy_context(rows).pause_requested_at(batch_id)
        end

        def workflow_approval_decision_for(rows, job_id)
          workflow_policy_context(rows).approval_decision_for(job_id)
        end

        def workflow_approval_decisions(rows, registration)
          workflow_policy_context(rows).approval_decisions(registration)
        end

        def workflow_interaction_delivered?(rows, batch_id:, kind:, name:)
          workflow_policy_context(rows).interaction_delivered?(batch_id:, kind:, name:)
        end

        def workflow_interaction_received_at_by_job_id(rows, batch_id, registration)
          workflow_policy_context(rows).interaction_received_at_by_job_id(batch_id, registration)
        end

        def workflow_rollback_snapshot(rows, batch_id)
          workflow_policy_context(rows).rollback_snapshot(batch_id)
        end

        def workflow_policy_context(rows)
          PolicyContext.new(rows:)
        end

        def workflow_history_builder(rows)
          WorkflowHistoryBuilder.new(host: self, rows:)
        end

        def workflow_row_mutator(rows)
          WorkflowRowMutator.new(host: self, store:, rows:)
        end

        def workflow_child_relationships(rows)
          WorkflowChildRelationships.new(host: self, rows:)
        end
      end
    end
  end
end
