# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Workflow interaction delivery operations build durable rows from normalized request state.

        # Collected durable auto-approval rows created while delivering a workflow signal.
        class WorkflowSignalApprovalRows
          attr_reader :policy_rows, :history_rows

          def initialize(policy_rows:, history_rows:)
            @policy_rows = policy_rows
            @history_rows = history_rows
          end
        end

        # Builds durable workflow approval side effects triggered by a workflow signal.
        class WorkflowSignalApprovalBuilder
          def initialize(operation:, interaction_request:)
            @operation = operation
            @interaction_request = interaction_request
          end

          def build
            policy_rows = []
            history_rows = []

            registration.approval_requirements_by_job_id.each do |job_id, requirement|
              next unless requirement.fetch(:name) == interaction_request.name
              next if rejected_decision?(job_id)

              append_auto_approval(job_id, policy_rows, history_rows)
            end

            WorkflowSignalApprovalRows.new(policy_rows:, history_rows:)
          end

          private

          attr_reader :operation, :interaction_request

          def registration
            interaction_request.registration
          end

          def namespace
            interaction_request.namespace
          end

          def batch_id
            interaction_request.batch_id
          end

          def now
            interaction_request.now
          end

          def working_rows
            @working_rows ||= begin
              source_rows = interaction_request.rows
              source_rows.merge(workflow_history: source_rows.fetch(:workflow_history).dup)
            end
          end

          def append_auto_approval(job_id, policy_rows, history_rows)
            policy_rows << operation.send(
              :build_workflow_approval_row,
              namespace:,
              job_id:,
              state: :approved,
              decided_at: now
            )
            history_row = auto_approval_history_row(job_id)
            history_rows << history_row
            working_rows.fetch(:workflow_history) << history_row
          end

          def auto_approval_history_row(job_id)
            operation.send(
              :workflow_control_row,
              rows: working_rows,
              namespace:,
              batch_id:,
              entry: WorkflowControlEntryBuilder.new(
                registration:,
                batch_id:,
                occurred_at: now,
                entry: {
                  kind: :control,
                  action: :approval_approved,
                  step_id: registration.step_id_by_job_id[job_id],
                  job_id:,
                  details: auto_approval_details
                }
              ).build
            )
          end

          def rejected_decision?(job_id)
            operation.send(:workflow_approval_decision_for, interaction_request.rows, job_id)&.state == :rejected
          end

          def auto_approval_details
            { 'auto_approved_via' => 'signal', 'signal_name' => interaction_request.name }
          end
        end
      end
    end
  end
end
