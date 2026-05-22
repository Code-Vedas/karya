# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'workflow_registration_builder'
require_relative 'workflow_queue_job_insert_builder'
require_relative 'workflow_enqueue_insert_builder'
require_relative 'workflow_flow_report_builder'
require_relative 'workflow_enqueue_result_builder'

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds workflow enqueue rows and enqueue-style mutation results.
        module WorkflowEnqueueSupport
          private

          def workflow_binding_for(definition)
            Workflow.send(
              :build_compensated_execution_binding,
              definition:,
              jobs_by_step_id: request.fetch(:jobs_by_step_id),
              batch_id: request.fetch(:batch_id),
              compensation_jobs_by_step_id: request.fetch(:compensation_jobs_by_step_id, {})
            )
          end
        end
      end
    end
  end
end
