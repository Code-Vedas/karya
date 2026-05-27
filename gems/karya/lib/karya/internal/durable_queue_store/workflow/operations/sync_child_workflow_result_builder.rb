# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Accumulates durable child-workflow sync outcomes across parent jobs.
        class SyncChildWorkflowAccumulator
          attr_reader :rows, :plans, :history_rows, :changed_jobs

          def initialize(operation:, rows:)
            @operation = operation
            @rows = rows
            @plans = []
            @history_rows = []
            @changed_jobs = []
          end

          def skip(skipped_jobs, transition, job_id)
            skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(
              job_id:,
              reason: :ineligible_state,
              state: transition.parent_job.state
            ).to_h
            rows
          end

          def apply_change(history_request, report_changed_jobs, job_id, transition)
            mutated_job = transition.mutated_job
            report_changed_jobs << mutated_job
            changed_jobs << mutated_job
            plans << operation.send(:storeable_plan_for_job, history_request.context, rows, mutated_job)
            history_rows << SyncChildWorkflowHistoryRowBuilder.new(
              operation:,
              context: SyncChildWorkflowHistoryContext.new(
                rows:,
                history_rows:,
                request: history_request
              ),
              job_id:,
              transition:
            ).build
            @rows = Operations::JobRuntimeRows.new(namespace: rows.fetch(:namespace), rows:).replace(
              job_id:,
              replacement_job: mutated_job
            )
          end

          private

          attr_reader :operation
        end

        # Immutable history context for one child-workflow sync row.
        SyncChildWorkflowHistoryRequest = Struct.new(
          :context,
          :namespace,
          :parent_batch_id,
          :parent_registration,
          :now,
          keyword_init: true
        )

        # Immutable row-building context for one synced child-workflow history entry.
        SyncChildWorkflowHistoryContext = Struct.new(
          :rows,
          :history_rows,
          :request,
          keyword_init: true
        )

        # Builds a workflow history row for one child-workflow sync mutation.
        class SyncChildWorkflowHistoryRowBuilder
          def initialize(operation:, context:, job_id:, transition:)
            @operation = operation
            @context = context
            @job_id = job_id
            @transition = transition
          end

          def build
            operation.send(
              :workflow_control_row,
              rows: rows.merge(workflow_history: rows.fetch(:workflow_history) + history_rows),
              namespace: request.namespace,
              batch_id: parent_batch_id,
              entry: WorkflowControlEntryBuilder.new(
                registration: request.parent_registration,
                batch_id: parent_batch_id,
                occurred_at: request.now,
                entry: {
                  kind: :child_workflow,
                  action: transition.action,
                  job_id:,
                  child_batch_id: transition.child_batch_id,
                  details: transition.details
                }
              ).build
            )
          end

          private

          attr_reader :operation, :context, :job_id, :transition

          def rows = context.rows
          def history_rows = context.history_rows
          def request = context.request

          def parent_batch_id
            request.parent_batch_id
          end
        end

        # Builds the final mutation plan for a child-workflow sync sweep.
        class SyncChildWorkflowMutationPlanBuilder
          def initialize(base_plan:, history_rows:)
            @base_plan = base_plan
            @history_rows = history_rows
          end

          def build
            MutationPlan.new(
              metadata_updates: base_plan.metadata_updates,
              inserts: base_plan.inserts.merge(workflow_history: history_rows),
              updates: base_plan.updates,
              deletes: base_plan.deletes
            )
          end

          private

          attr_reader :base_plan, :history_rows
        end

        # Builds the public report and change flag for a synced child-workflow sweep.
        class SyncChildWorkflowReportBuilder
          def initialize(operation:, request:, accumulator:)
            @operation = operation
            @request = request
            @accumulator = accumulator
          end

          def build
            now = request.now
            report = Karya::Internal::BulkMutation::ReportBuilder.new(
              action: :sync_child_workflows,
              job_ids: request.relationships.map(&:parent_job_id),
              now:
            ).to_report do |job_id, report_changed_jobs, skipped_jobs|
              transition = SyncChildWorkflowTransitionBuilder.new(
                operation:,
                rows: accumulator.rows,
                job_id:,
                now:
              ).build
              if transition.mutated_job
                accumulator.apply_change(history_request, report_changed_jobs, job_id, transition)
              else
                accumulator.skip(skipped_jobs, transition, job_id)
              end
            end
            [report, accumulator.changed_jobs.any?]
          end

          private

          attr_reader :operation, :request, :accumulator

          def history_request
            @history_request ||= SyncChildWorkflowHistoryRequest.new(
              context: request.context,
              namespace: request.namespace,
              parent_batch_id: request.parent_batch_id,
              parent_registration: request.parent_registration,
              now: request.now
            )
          end
        end

        # Builds the durable report and mutation plan for one child-workflow sync sweep.
        class SyncChildWorkflowResultBuilder
          def initialize(operation:, request:)
            @operation = operation
            @request = request
          end

          def build
            accumulator = SyncChildWorkflowAccumulator.new(operation:, rows: request.rows)
            report, changed = SyncChildWorkflowReportBuilder.new(
              operation:,
              request:,
              accumulator:
            ).build

            [
              report,
              SyncChildWorkflowMutationPlanBuilder.new(
                base_plan: operation.send(:combine_plans, accumulator.plans),
                history_rows: accumulator.history_rows
              ).build,
              changed
            ]
          end

          private

          attr_reader :operation, :request
        end
      end
    end
  end
end
