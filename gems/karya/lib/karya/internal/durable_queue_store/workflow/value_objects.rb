# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        WORKFLOW_INTERACTION_TERMINAL_STATES = %i[succeeded failed cancelled].freeze
        ACTIVE_JOB_STATES = %i[reserved running retry_pending].freeze
        WAITING_JOB_STATES = %i[queued submission].freeze
        ROLLBACK_BATCH_PREFIX = '__karya_workflow_rollback_v1__'

        # Immutable registration metadata reconstructed from durable workflow rows.
        WorkflowRegistration = Struct.new(
          :workflow_id,
          :workflow_family,
          :workflow_version,
          :step_job_ids,
          :step_id_by_job_id,
          :dependency_job_ids_by_job_id,
          :approval_requirements_by_job_id,
          :interaction_requirements_by_job_id,
          :interaction_supported_keys,
          :compensation_jobs_by_step_id,
          :child_workflow_ids_by_step_id
        )

        # Durable approval decision for a workflow checkpoint job.
        WorkflowApprovalDecision = Struct.new(:job_id, :state, :decided_at, :reason) do
          def self.approved(job_id:, decided_at:)
            new(job_id, :approved, decided_at, nil).freeze
          end

          def self.rejected(job_id:, decided_at:, reason:)
            new(job_id, :rejected, decided_at, reason).freeze
          end

          def to_snapshot_decision
            return { state:, decided_at: }.freeze unless reason

            { state:, decided_at:, reason: }.freeze
          end
        end

        # Durable parent-child linkage between workflow batches.
        WorkflowChildRelationship = Struct.new(
          :parent_workflow_id,
          :parent_workflow_family,
          :parent_workflow_version,
          :parent_batch_id,
          :parent_step_id,
          :parent_job_id,
          :child_workflow_id,
          :child_workflow_family,
          :child_workflow_version,
          :child_batch_id,
          keyword_init: true
        )
      end
    end
  end
end
