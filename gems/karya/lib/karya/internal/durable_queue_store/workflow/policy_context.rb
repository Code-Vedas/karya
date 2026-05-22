# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Reads workflow control-plane state from durable policy and interaction rows.
        class PolicyContext
          # Matches durable policy rows for one policy kind and scope pair.
          class PolicyRowMatcher
            def initialize(policy_kind:, scope_kind:, scope_value:)
              @policy_kind = policy_kind
              @scope_kind = scope_kind
              @scope_value = scope_value
            end

            def matches?(row)
              row.fetch(:policy_kind) == policy_kind &&
                row.fetch(:scope_kind) == scope_kind &&
                row.fetch(:scope_value) == scope_value
            end

            private

            attr_reader :policy_kind, :scope_kind, :scope_value
          end

          # Wraps one decoded durable workflow policy payload.
          class PolicyPayloadView
            def initialize(payload:)
              @payload = payload
            end

            def value(key)
              payload[key.to_s] || payload[key]
            end

            def requested_at
              value(:requested_at)
            end

            private

            attr_reader :payload
          end

          # Converts one durable approval payload into a workflow approval decision.
          class ApprovalDecisionBuilder
            def initialize(job_id:, payload:)
              @job_id = job_id
              @payload = PolicyPayloadView.new(payload:)
            end

            def build
              if state == :approved
                WorkflowApprovalDecision.approved(job_id:, decided_at:)
              else
                WorkflowApprovalDecision.rejected(job_id:, decided_at:, reason:)
              end
            end

            private

            attr_reader :job_id, :payload

            def state
              @state ||= payload_value(:state).to_sym
            end

            def decided_at
              payload_value(:decided_at)
            end

            def reason
              payload_value(:reason)
            end

            def payload_value(key)
              payload.value(key)
            end
          end

          # Builds the approval-decision snapshot map for a workflow registration.
          class ApprovalDecisionsBuilder
            def initialize(context:, registration:)
              @context = context
              @registration = registration
            end

            def build
              registration.approval_requirements_by_job_id.each_with_object({}) do |(job_id, _requirement), decisions|
                decision = context.approval_decision_for(job_id)
                decisions[job_id] = decision.to_snapshot_decision if decision
              end.freeze
            end

            private

            attr_reader :context, :registration
          end

          # Indexes workflow interactions for one batch to answer delivery and received-at queries.
          class InteractionIndex
            # Normalizes one workflow interaction requirement into lookup keys.
            class Requirement
              def initialize(requirement:)
                @requirement = requirement
              end

              def interaction_for(index)
                index.interaction_for(kind:, name:)
              end

              def kind
                requirement.fetch(:kind)
              end

              def name
                requirement.fetch(:name)
              end

              private

              attr_reader :requirement
            end

            # Matches one workflow interaction row against a normalized lookup key.
            class Matcher
              def initialize(kind:, name:)
                @kind = kind
                @name = name
              end

              def matches?(row)
                row.fetch(:kind).to_sym == kind.to_sym &&
                  row.fetch(:name) == name
              end

              private

              attr_reader :kind, :name
            end

            # Builds the received-at map for one workflow registration from indexed interactions.
            class ReceiptsBuilder
              def initialize(index:, registration:)
                @index = index
                @registration = registration
              end

              def build
                registration.interaction_requirements_by_job_id.each_with_object({}) do |(job_id, requirement), received|
                  interaction = index.interaction_for_requirement(requirement)
                  received[job_id] = interaction.fetch(:received_at) if interaction
                end.freeze
              end

              private

              attr_reader :index, :registration
            end

            def initialize(rows:, batch_id:)
              @rows = rows
              @batch_id = batch_id
            end

            def delivered?(kind:, name:)
              !!interaction_for(kind:, name:)
            end

            def received_at_by_job_id(registration)
              ReceiptsBuilder.new(index: self, registration:).build
            end

            private

            attr_reader :rows, :batch_id

            def interactions
              @interactions ||= rows.fetch(:workflow_interactions).select do |row|
                row.fetch(:batch_id) == batch_id
              end
            end

            def interaction_for(kind:, name:)
              matcher = Matcher.new(kind:, name:)
              interactions.find { |row| matcher.matches?(row) }
            end

            def interaction_for_requirement(requirement)
              Requirement.new(requirement:).interaction_for(self)
            end

            public :interaction_for
            public :interaction_for_requirement
          end

          # Rebuilds a workflow rollback snapshot from one decoded durable payload.
          class RollbackSnapshotBuilder
            def initialize(payload:)
              @payload = PolicyPayloadView.new(payload:)
            end

            def build
              Workflow::RollbackSnapshot.new(
                workflow_batch_id: payload.value(:batch_id),
                rollback_batch_id: payload.value(:rollback_batch_id),
                reason: payload.value(:reason),
                requested_at: payload.requested_at,
                compensation_job_ids: payload.value(:compensation_job_ids)
              )
            end

            private

            attr_reader :payload
          end

          def initialize(rows:)
            @rows = rows
          end

          def pause_requested_at(batch_id)
            payload = policy_payload('workflow_pause', 'workflow', batch_id)
            payload && PolicyPayloadView.new(payload:).requested_at
          end

          def approval_decision_for(job_id)
            payload = policy_payload('workflow_approval_decision', 'job', job_id)
            return nil unless payload

            ApprovalDecisionBuilder.new(job_id:, payload:).build
          end

          def approval_decisions(registration)
            ApprovalDecisionsBuilder.new(context: self, registration:).build
          end

          def interaction_delivered?(batch_id:, kind:, name:)
            interaction_index(batch_id).delivered?(kind:, name:)
          end

          def interaction_received_at_by_job_id(batch_id, registration)
            interaction_index(batch_id).received_at_by_job_id(registration)
          end

          def rollback_snapshot(batch_id)
            payload = policy_payload('workflow_rollback', 'workflow', batch_id)
            return nil unless payload

            RollbackSnapshotBuilder.new(payload:).build
          end

          private

          attr_reader :rows

          def interaction_index(batch_id)
            @interaction_indexes ||= {}
            @interaction_indexes[batch_id] ||= InteractionIndex.new(rows:, batch_id:)
          end

          def policy_payload(policy_kind, scope_kind, scope_value)
            matcher = PolicyRowMatcher.new(policy_kind:, scope_kind:, scope_value:)
            row = rows.fetch(:policy_state, []).find { |candidate| matcher.matches?(candidate) }
            Operations::PolicyStateRow.new(row:).payload(default: nil)
          end
        end
      end
    end
  end
end
