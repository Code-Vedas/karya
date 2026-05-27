# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Rebuilds workflow registration metadata from durable rows.
        module RegistrationLoader
          private

          def registration_for_batch(rows, batch_id)
            batch_row = workflow_batch_row(rows, batch_id)
            raise Workflow::InvalidExecutionError, "batch #{batch_id.inspect} is not a workflow batch" unless batch_row

            RegistrationBuilder.new(
              batch_row:,
              step_rows: workflow_step_rows_for_batch(rows, batch_id)
            ).build
          end

          def interaction_supported_keys(approval_requirements_by_job_id, interaction_requirements_by_job_id)
            InteractionSupportedKeysBuilder.new(
              approval_requirements_by_job_id:,
              interaction_requirements_by_job_id:
            ).to_h
          end
        end
      end
    end
  end
end
