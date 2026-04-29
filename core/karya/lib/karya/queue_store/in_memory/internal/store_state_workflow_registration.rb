# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Owner-local workflow registration and approval metadata for StoreState.
        class StoreState
          # Immutable owner-local workflow registration metadata for one batch.
          WorkflowRegistration = Struct.new(
            :workflow_id,
            :workflow_family,
            :workflow_version,
            :step_job_ids,
            :dependency_job_ids_by_job_id,
            :approval_requirements_by_job_id,
            :interaction_requirements_by_job_id,
            :interaction_supported_keys,
            :compensation_jobs_by_step_id,
            :child_workflow_ids_by_step_id
          ) do
            def self.build(
              workflow_id:,
              step_job_ids:,
              dependency_job_ids_by_job_id:,
              approval_requirements_by_job_id:,
              interaction_requirements_by_job_id:,
              compensation_jobs_by_step_id:,
              child_workflow_ids_by_step_id:,
              workflow_family: workflow_id,
              workflow_version: 'v1'
            )
              approvals = WorkflowRegistrationRequirements.new(approval_requirements_by_job_id).to_h
              interactions = WorkflowRegistrationRequirements.new(interaction_requirements_by_job_id).to_h
              approval_supported_keys = ApprovalSupportedKeys.new(approvals).to_h

              new(
                workflow_id,
                workflow_family,
                workflow_version,
                step_job_ids.dup.freeze,
                dependency_job_ids_by_job_id.transform_values { |dependency_job_ids| dependency_job_ids.dup.freeze }.freeze,
                approvals,
                interactions,
                InteractionSupportedKeys.new(interactions).to_h
                  .merge(approval_supported_keys)
                  .freeze,
                compensation_jobs_by_step_id.dup.freeze,
                child_workflow_ids_by_step_id.dup.freeze
              )
            end
          end

          # Immutable owner-local approval decision metadata for one workflow job.
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

          # Duplicates and freezes workflow registration requirement hashes.
          class WorkflowRegistrationRequirements
            def initialize(requirements)
              @requirements = requirements
            end

            def to_h
              requirements.transform_values { |requirement| RequirementCopy.new(requirement).to_h }.freeze
            end

            private

            attr_reader :requirements

            # Copies one registration requirement into an immutable normalized hash.
            class RequirementCopy
              def initialize(requirement)
                @requirement = requirement
              end

              def to_h
                name = requirement.fetch(:name)
                requirement.dup.tap { |copy| copy[:name] = name }.freeze
              end

              private

              attr_reader :requirement
            end

            private_constant :RequirementCopy
          end

          # Builds supported signal keys for approval-compatible checkpoints.
          class ApprovalSupportedKeys
            def initialize(approvals)
              @approvals = approvals
            end

            def to_h
              approvals.values.to_h do |requirement|
                [[:signal, requirement[:name]], true]
              end
            end

            private

            attr_reader :approvals
          end

          # Builds supported interaction keys for declared workflow inbox entries.
          class InteractionSupportedKeys
            def initialize(interactions)
              @interactions = interactions
            end

            def to_h
              interactions.values.to_h { |requirement| SupportedKey.new(requirement).to_h }
            end

            private

            attr_reader :interactions

            # Builds one immutable inbox-supported key entry.
            class SupportedKey
              def initialize(requirement)
                @requirement = requirement
              end

              def to_h
                [[requirement.fetch(:kind), requirement[:name]], true]
              end

              private

              attr_reader :requirement
            end

            private_constant :SupportedKey
          end

          private_constant :ApprovalSupportedKeys,
                           :InteractionSupportedKeys,
                           :WorkflowApprovalDecision,
                           :WorkflowRegistration,
                           :WorkflowRegistrationRequirements
        end
      end
    end
  end
end
