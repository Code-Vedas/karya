# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Mutable state captured while a workflow-step bulk operation iterates step jobs.
        class WorkflowStepBulkAccumulator
          attr_reader :changed_jobs, :plans, :history_rows

          def initialize
            @changed_jobs = []
            @plans = []
            @history_rows = []
          end

          def apply_change(report_changed_jobs, mutated_job, plan, history_row)
            report_changed_jobs << mutated_job
            changed_jobs << mutated_job
            plans << plan
            history_rows << history_row
          end
        end

        # Builds history rows for workflow-step bulk-control mutations.
        class WorkflowStepBulkHistoryRowBuilder
          def initialize(operation:, request:, rows:, job_id:, accumulator:)
            @operation = operation
            @request = request
            @rows = rows
            @job_id = job_id
            @accumulator = accumulator
          end

          def build
            batch_id = request.batch_id
            registration = request.registration
            step_id = registration.step_id_by_job_id[job_id]
            operation.send(
              :workflow_control_row,
              rows: rows.merge(workflow_history: rows.fetch(:workflow_history) + accumulator.history_rows),
              namespace: request.context.namespace,
              batch_id:,
              entry: WorkflowControlEntryBuilder.new(
                registration:,
                batch_id:,
                occurred_at: request.now,
                entry: {
                  kind: :control,
                  action: request.action,
                  step_id:,
                  job_id:
                }
              ).build
            )
          end

          private

          attr_reader :operation, :request, :rows, :job_id, :accumulator
        end

        # Builds WorkflowBulkMutation objects from current runtime rows.
        class WorkflowStepBulkMutationBuilder
          def self.build(rows:, job_id:, skipped_jobs:)
            WorkflowStepBulkOperation::WorkflowBulkMutation.new(
              job: Operations::JobRow.new(row: Operations::RowIndex.new(rows:).jobs_by_id.fetch(job_id)).to_job,
              rows:,
              skipped_jobs:,
              job_id:
            )
          end
        end

        # Merges per-step mutation plans into one persisted workflow-step bulk mutation plan.
        class WorkflowStepBulkPlanBuilder
          def initialize(operation:, accumulator:)
            @operation = operation
            @accumulator = accumulator
          end

          def build
            MutationPlan.new(
              metadata_updates: base_plan.metadata_updates,
              inserts: base_plan.inserts.merge(workflow_history: accumulator.history_rows),
              updates: base_plan.updates,
              deletes: base_plan.deletes
            )
          end

          private

          attr_reader :operation, :accumulator

          def base_plan
            @base_plan ||= operation.send(:combine_plans, accumulator.plans)
          end
        end

        # Builds the report and evolving rows for workflow-step bulk-control operations.
        class WorkflowStepBulkReportBuilder
          def initialize(operation:, request:, accumulator:, transition_block:)
            @operation = operation
            @request = request
            @accumulator = accumulator
            @transition_block = transition_block
          end

          def build
            rows = request.rows
            context = request.context
            report = Karya::Internal::BulkMutation::ReportBuilder.new(
              action: request.action,
              job_ids: request.job_ids,
              now: request.now
            ).to_report do |job_id, report_changed_jobs, skipped_jobs|
              rows = apply_mutation(rows, context, job_id, report_changed_jobs, skipped_jobs)
            end

            [report, accumulator.changed_jobs.any?]
          end

          private

          attr_reader :operation, :request, :accumulator, :transition_block

          def apply_mutation(rows, context, job_id, report_changed_jobs, skipped_jobs)
            mutation = WorkflowStepBulkMutationBuilder.build(rows:, job_id:, skipped_jobs:)
            mutated_job = transition_block.call(mutation)
            return rows unless mutated_job

            accumulator.apply_change(
              report_changed_jobs,
              mutated_job,
              operation.send(:storeable_plan_for_job, context, rows, mutated_job),
              WorkflowStepBulkHistoryRowBuilder.new(
                operation:,
                request:,
                rows:,
                job_id:,
                accumulator:
              ).build
            )
            Operations::JobRuntimeRows.new(namespace: context.namespace, rows:).replace(
              job_id:,
              replacement_job: mutated_job
            )
          end
        end
      end
    end
  end
end
