# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Builds one durable workflow-step row from registration and runtime state.
      class WorkflowStepRecord
        EMPTY_DEPENDENCY_JOB_IDS = [].freeze

        # Bundles workflow registration and store state for one step projection.
        class Context
          def initialize(registration:, state:)
            @registration = registration
            @state = state
          end

          attr_reader :registration, :state
        end

        # Builds one immutable rollback payload for workflow-step metadata.
        class RollbackPayload
          def initialize(rollback)
            @rollback = rollback
          end

          def to_h
            {
              'rollback_batch_id' => rollback.rollback_batch_id,
              'reason' => rollback.reason,
              'requested_at' => rollback.requested_at,
              'compensation_job_ids' => rollback.compensation_job_ids
            }.freeze
          end

          private

          attr_reader :rollback
        end
        private_constant :RollbackPayload

        def initialize(namespace:, batch_id:, step_id:, job:, context:)
          @namespace = namespace
          @batch_id = batch_id
          @step_id = step_id
          @job = job
          @context = context
        end

        def to_h
          {
            namespace:,
            batch_id:,
            step_id:,
            step_sequence: step_sequence,
            job_id: job.id,
            state: job.state.to_s,
            dependency_payload: PayloadCodec.dump(dependency_job_ids),
            metadata_payload: PayloadCodec.dump(step_metadata),
            updated_at: job.updated_at
          }
        end

        private

        attr_reader :batch_id, :context, :job, :namespace, :step_id

        def registration
          context.registration
        end

        def state
          context.state
        end

        def dependency_job_ids
          registration.dependency_job_ids_by_job_id.fetch(job.id, EMPTY_DEPENDENCY_JOB_IDS)
        end

        def step_sequence
          @step_sequence ||= registration.step_job_ids.keys.index(step_id) + 1
        end

        def step_metadata
          job_id = job.id
          {
            'approval_decision' => approval_decision_payload(job_id),
            'approval_requirement' => registration.approval_requirements_by_job_id[job_id],
            'interaction_requirement' => registration.interaction_requirements_by_job_id[job_id],
            'interaction_received_at' => interaction_received_at,
            'compensation_job_id' => registration.compensation_jobs_by_step_id[step_id],
            'child_workflow_id' => registration.child_workflow_ids_by_step_id[step_id],
            'pause_requested_at' => state.workflow_pause_requested_at(batch_id),
            'rollback' => rollback_payload
          }.freeze
        end

        def approval_decision_payload(job_id)
          state.workflow_approval_decision_for(job_id)&.to_snapshot_decision
        end

        def interaction_received_at
          requirement = registration.interaction_requirements_by_job_id[job.id]
          return unless requirement

          state.workflow_interaction_received_at(
            batch_id:,
            kind: requirement.fetch(:kind),
            name: requirement.fetch(:name)
          )
        end

        def rollback_payload
          rollback = state.workflow_rollbacks_by_batch_id[batch_id]
          rollback && RollbackPayload.new(rollback).to_h
        end
      end
    end
  end
end
