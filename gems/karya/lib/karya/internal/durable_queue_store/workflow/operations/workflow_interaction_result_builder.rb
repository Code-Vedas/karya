# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds the durable result for one workflow signal or event delivery.
        class WorkflowInteractionResultBuilder
          def initialize(action:, interaction_row:, history_row:, approval_rows:, interaction_request:)
            @action = action
            @interaction_row = interaction_row
            @history_row = history_row
            @approval_rows = approval_rows
            @interaction_request = interaction_request
          end

          def build
            OperationResult.new(
              value: WorkflowFlowReportBuilder.new(
                action:,
                now: interaction_request.now,
                requested_job_ids: [],
                changed_jobs: [],
                skipped_jobs: []
              ).build,
              mutation_plan: MutationPlan.new(
                inserts: {
                  workflow_interactions: [interaction_row],
                  workflow_history: [history_row] + approval_rows.history_rows,
                  policy_state: approval_rows.policy_rows
                }
              ),
              persist: true
            )
          end

          private

          attr_reader :action, :interaction_row, :history_row, :approval_rows, :interaction_request
        end
      end
    end
  end
end
