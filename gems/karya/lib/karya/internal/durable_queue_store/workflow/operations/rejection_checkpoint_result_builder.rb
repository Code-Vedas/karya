# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Mutable report state for workflow checkpoint rejection.
        class RejectionCheckpointAccumulator
          attr_reader :changed_jobs, :plans, :history_rows

          def initialize
            @changed_jobs = []
            @plans = []
            @history_rows = []
          end

          def apply_change(report_changed_jobs, cancelled_job, plan, history_row)
            report_changed_jobs << cancelled_job
            changed_jobs << cancelled_job
            plans << plan
            history_rows << history_row
          end
        end

        # Validates and materializes one workflow checkpoint rejection change.
        class RejectionCheckpointProcessor
          def initialize(operation:, request:, accumulator:)
            @operation = operation
            @request = request
            @accumulator = accumulator
          end

          def process(rows:, job_id:, report_changed_jobs:, report_skipped_jobs:)
            step_id = request.registration.step_id_by_job_id[job_id]
            step_snapshot = request.snapshot.fetch_step(step_id)
            validate_checkpoint(step_id, step_snapshot, job_id)
            job = Operations::JobRow.new(row: Operations::RowIndex.new(rows:).jobs_by_id.fetch(job_id)).to_job
            unless job.can_transition_to?(:cancelled)
              report_skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(
                job_id:,
                reason: :ineligible_state,
                state: job.state
              ).to_h
              return rows
            end

            apply_change(rows:, job_id:, step_id:, job:, report_changed_jobs:)
          end

          private

          attr_reader :operation, :request, :accumulator

          def validate_checkpoint(step_id, step_snapshot, job_id)
            unless request.registration.approval_requirements_by_job_id[job_id]
              raise Workflow::InvalidExecutionError, "workflow step #{step_id.inspect} is not an approval checkpoint"
            end
            return if step_snapshot.awaiting_approval?

            raise Workflow::InvalidExecutionError, "workflow step #{step_snapshot.step_id.inspect} is not awaiting approval"
          end

          def apply_change(rows:, job_id:, step_id:, job:, report_changed_jobs:)
            cancelled_job = job.transition_to(:cancelled, updated_at: request.now, next_retry_at: nil, failure_classification: nil)
            plan = operation.send(:storeable_plan_for_job, request.context, rows, cancelled_job)
            history_row = rejection_history_row(rows:, job_id:, step_id:)
            accumulator.apply_change(report_changed_jobs, cancelled_job, plan, history_row)
            Operations::JobRuntimeRows.new(namespace: rows.fetch(:namespace), rows:).replace(
              job_id:,
              replacement_job: cancelled_job
            )
          end

          def rejection_history_row(rows:, job_id:, step_id:)
            batch_id = request.batch_id
            operation.send(
              :workflow_control_row,
              rows: rows.merge(workflow_history: rows.fetch(:workflow_history) + accumulator.history_rows),
              namespace: request.context.namespace,
              batch_id:,
              entry: WorkflowControlEntryBuilder.new(
                registration: request.registration,
                batch_id:,
                occurred_at: request.now,
                entry: {
                  kind: :control,
                  action: :approval_rejected,
                  step_id:,
                  job_id:,
                  details: { 'reason' => request.reason }
                }
              ).build
            )
          end
        end

        # Builds the persisted mutation plan for workflow checkpoint rejection.
        class RejectionCheckpointPlanBuilder
          def initialize(operation:, request:, accumulator:)
            @operation = operation
            @request = request
            @accumulator = accumulator
          end

          def build
            approval_rows = accumulator.changed_jobs.map do |job|
              operation.send(
                :build_workflow_approval_row,
                namespace: request.context.namespace,
                job_id: job.id,
                state: :rejected,
                decided_at: request.now,
                reason: request.reason
              )
            end
            base_inserts = base_plan.inserts
            MutationPlan.new(
              inserts: base_inserts.merge(
                policy_state: base_inserts.fetch(:policy_state, []) + approval_rows,
                workflow_history: accumulator.history_rows
              ),
              updates: base_plan.updates,
              deletes: base_plan.deletes,
              metadata_updates: base_plan.metadata_updates
            )
          end

          private

          attr_reader :operation, :request, :accumulator

          def base_plan
            @base_plan ||= operation.send(:combine_plans, accumulator.plans)
          end
        end

        # Builds the report, mutated rows, and persisted plan for rejection operations.
        class RejectionCheckpointResultBuilder
          def initialize(operation:, request:)
            @operation = operation
            @request = request
            @accumulator = RejectionCheckpointAccumulator.new
          end

          def build
            rows = request.rows
            report = Karya::Internal::BulkMutation::ReportBuilder.new(
              action: :reject_workflow_checkpoints,
              job_ids: request.job_ids,
              now: request.now
            ).to_report do |job_id, report_changed_jobs, report_skipped_jobs|
              rows = processor.process(
                rows:,
                job_id:,
                report_changed_jobs:,
                report_skipped_jobs:
              )
            end

            [report, plan_builder.build, accumulator.changed_jobs.any?]
          end

          private

          attr_reader :operation, :request, :accumulator

          def processor
            @processor ||= RejectionCheckpointProcessor.new(operation:, request:, accumulator:)
          end

          def plan_builder
            @plan_builder ||= RejectionCheckpointPlanBuilder.new(operation:, request:, accumulator:)
          end
        end
      end
    end
  end
end
