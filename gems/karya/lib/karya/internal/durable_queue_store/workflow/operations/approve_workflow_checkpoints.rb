# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Persists approval decisions for workflow checkpoint steps.
        class ApproveWorkflowCheckpoints < Operation
          include WorkflowOperationSupport

          def call(context:)
            now = normalized_workflow_now
            batch_id, rows, registration, snapshot, job_ids = workflow_checkpoint_context(context, now)
            report, history_rows = approval_checkpoint_report(
              context,
              batch_id,
              rows,
              registration,
              snapshot,
              job_ids,
              now
            )

            OperationResult.new(
              value: report,
              mutation_plan: MutationPlan.new(
                inserts: {
                  policy_state: job_ids.map { |job_id| build_workflow_approval_row(namespace: context.namespace, job_id:, state: :approved, decided_at: now) },
                  workflow_history: history_rows
                }
              ),
              persist: true
            )
          end

          private

          def workflow_checkpoint_context(context, now)
            batch_id = normalized_workflow_batch_id
            rows = context.rows.merge(namespace: context.namespace)
            _batch, registration, snapshot = workflow_target(batch_id, rows, now)
            [batch_id, rows, registration, snapshot, workflow_control_job_ids(registration, request.fetch(:step_ids))]
          end

          def approval_checkpoint_report(context, batch_id, rows, registration, snapshot, job_ids, now)
            history_rows = []
            report = Karya::Internal::BulkMutation::ReportBuilder.new(
              action: :approve_workflow_checkpoints,
              job_ids:,
              now:
            ).to_report do |job_id, _changed_jobs, _skipped_jobs|
              step_id = registration.step_id_by_job_id[job_id]
              step_snapshot = snapshot.fetch_step(step_id)
              validate_approval_checkpoint(registration, step_id, step_snapshot, job_id)

              history_rows << workflow_control_row(
                rows: rows.merge(workflow_history: rows.fetch(:workflow_history) + history_rows),
                namespace: context.namespace,
                batch_id:,
                entry: WorkflowControlEntryBuilder.new(
                  registration:,
                  batch_id:,
                  occurred_at: now,
                  entry: { kind: :control, action: :approval_approved, step_id:, job_id: }
                ).build
              )
            end
            [report, history_rows]
          end

          def validate_approval_checkpoint(registration, step_id, step_snapshot, job_id)
            unless registration.approval_requirements_by_job_id[job_id]
              raise Workflow::InvalidExecutionError, "workflow step #{step_id.inspect} is not an approval checkpoint"
            end
            return if step_snapshot.awaiting_approval?

            raise Workflow::InvalidExecutionError, "workflow step #{step_snapshot.step_id.inspect} is not awaiting approval"
          end
        end
      end
    end
  end
end
