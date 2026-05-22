# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Executes one bulk job mutation while keeping row and plan updates together.
        class BulkMutationRunner
          def initialize(context:, action:, job_ids:, now:, host:, &mutation)
            @context = context
            @action = action
            @job_ids = job_ids
            @now = now
            @host = host
            @mutation = mutation
          end

          attr_reader :context, :action, :job_ids, :now, :host, :mutation

          def call
            changed_jobs = []
            plans = []
            rows = context.rows.merge(namespace: context.namespace)
            report = Karya::Internal::BulkMutation::ReportBuilder.new(action:, job_ids:, now:).to_report do |job_id, report_changed_jobs, skipped_jobs|
              rows, changed_job, plan = apply_one(rows, job_id, skipped_jobs)
              next unless changed_job

              report_changed_jobs << changed_job
              changed_jobs << changed_job
              plans << plan
            end

            OperationResult.new(value: report, mutation_plan: host.send(:combine_plans, plans), persist: !changed_jobs.empty?)
          end

          private

          def apply_one(rows, job_id, skipped_jobs)
            namespace = context.namespace
            job = BulkJobLookup.new(namespace:, rows:, job_id:, skipped_jobs:).load
            return [rows, nil, nil] unless job

            mutated_job = mutation.call(job, rows, skipped_jobs, job_id)
            return [rows, nil, nil] unless mutated_job

            [
              JobRuntimeRows.new(namespace:, rows:).replace(job_id:, replacement_job: mutated_job),
              mutated_job,
              host.send(:storeable_plan_for_job, context, rows, mutated_job)
            ]
          end
        end
      end
    end
  end
end
