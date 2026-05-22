# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'dependency_target'

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Evaluates workflow pause, dependency, interaction, approval, and child gates.
        class WorkflowDependencyEvaluator
          def initialize(host:, rows:, job:, now:, target: nil)
            @host = host
            @rows = rows
            @job = job
            @now = now
            @target = target
          end

          def satisfied?
            return true if step_rows.empty?
            return false if paused?
            return false unless child_satisfied?
            return false unless interaction_satisfied?
            return false unless approval_satisfied?

            dependency_job_ids.all? do |dependency_job_id|
              dependency_row = Operations::RowIndex.new(rows:).jobs_by_id[dependency_job_id]
              dependency_row && dependency_row.fetch(:state).to_sym == :succeeded
            end
          end

          def paused?
            !!host.send(:workflow_pause_requested_at, rows, batch_id)
          end

          def interaction_satisfied?
            requirement = registration.interaction_requirements_by_job_id[job.id]
            return true unless requirement

            host.send(:workflow_interaction_delivered?, rows, batch_id:, kind: requirement.fetch(:kind), name: requirement.fetch(:name))
          end

          def approval_satisfied?
            job_id = job.id
            requirement = registration.approval_requirements_by_job_id[job_id]
            return true unless requirement

            decision = host.send(:workflow_approval_decision_for, rows, job_id)
            return false if decision&.state == :rejected
            return true if decision&.state == :approved

            host.send(:workflow_interaction_delivered?, rows, batch_id:, kind: :signal, name: requirement.fetch(:name))
          end

          def child_satisfied?
            job_id = job.id
            child_workflow_id = registration.child_workflow_ids_by_step_id[registration.step_id_by_job_id[job_id]]
            return true unless child_workflow_id

            relationship = host.send(:child_relationship_for_parent_job, rows, job_id)
            return false unless relationship

            host.send(:workflow_state_for_batch, rows, relationship.child_batch_id, now, cache: {}, visiting: {}) == :succeeded
          end

          private

          attr_reader :host, :rows, :job, :now, :target

          def step_rows
            @step_rows ||= host.send(:workflow_step_rows_for_job, rows, job.id)
          end

          def batch_id
            @batch_id ||= target&.batch_id || step_rows.first.fetch(:batch_id)
          end

          def registration
            @registration ||= target&.registration || host.send(:registration_for_batch, rows, batch_id)
          end

          def dependency_job_ids
            Array(registration.dependency_job_ids_by_job_id[job.id])
          end
        end
      end
    end
  end
end
