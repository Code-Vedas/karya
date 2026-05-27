# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Builds the validated durable workflow rollback request context.
        class RollbackRequestBuilder
          def initialize(operation:, context:)
            @operation = operation
            @context = context
          end

          def build
            now, batch_id, rows, registration, snapshot = rollback_context
            validate_existing_rollbacks(rows, batch_id)
            operation.send(:validate_rollback_snapshot, snapshot, registration.dependency_job_ids_by_job_id)
            rollback_plan = rollback_plan(rows, batch_id, snapshot, registration, now)

            RollbackRequest.new(
              now:,
              batch_id:,
              rows:,
              rollback_plan:
            )
          end

          private

          attr_reader :operation, :context

          def rollback_context
            now = operation.send(:normalized_workflow_now)
            batch_id = operation.send(:normalized_workflow_batch_id)
            rows = context.rows.merge(namespace: context.namespace)
            _batch, registration, snapshot = operation.send(:workflow_target, batch_id, rows, now)
            [now, batch_id, rows, registration, snapshot]
          end

          def validate_existing_rollbacks(rows, batch_id)
            return unless operation.send(:workflow_rollback_snapshot, rows, batch_id)

            raise Workflow::DuplicateBatchError, "workflow batch #{batch_id.inspect} already has a rollback"
          end

          def rollback_plan(rows, batch_id, snapshot, registration, now)
            rollback_jobs = RollbackJobsBuilder.new(snapshot:, registration:).build
            queued_jobs = operation.send(:validate_workflow_enqueue_jobs, rows, rollback_jobs.map(&:last), now)
            rollback_batch_id = operation.send(:rollback_batch_id_for, batch_id)
            if operation.send(:workflow_batch_row, rows, rollback_batch_id)
              raise Workflow::DuplicateBatchError, "batch #{rollback_batch_id.inspect} already exists"
            end

            RollbackPlan.new(
              registration:,
              rollback_batch_id:,
              rollback_step_ids: rollback_jobs.map(&:first),
              queued_jobs:,
              reason: operation.request.fetch(:reason)
            )
          end
        end

        # Selects succeeded workflow steps that have compensation jobs for rollback.
        class RollbackJobsBuilder
          def initialize(snapshot:, registration:)
            @snapshot = snapshot
            @registration = registration
          end

          def build
            registration.step_job_ids.keys.reverse.filter_map do |step_id|
              primary_job = snapshot.job_for_step(step_id)
              next unless primary_job.state == :succeeded

              compensation_job = registration.compensation_jobs_by_step_id[step_id]
              compensation_job && [step_id, compensation_job]
            end
          end

          private

          attr_reader :snapshot, :registration
        end

        # Carries the validated rollback plan used to persist durable rollback rows.
        class RollbackPlan
          def initialize(registration:, rollback_batch_id:, rollback_step_ids:, queued_jobs:, reason:)
            @registration = registration
            @rollback_batch_id = rollback_batch_id
            @rollback_step_ids = rollback_step_ids
            @queued_jobs = queued_jobs
            @reason = reason
          end

          attr_reader :registration, :rollback_batch_id, :rollback_step_ids, :queued_jobs, :reason
        end

        # Carries the validated rollback state used to persist durable rollback rows.
        class RollbackRequest
          def initialize(now:, batch_id:, rows:, rollback_plan:)
            @now = now
            @batch_id = batch_id
            @rows = rows
            @rollback_plan = rollback_plan
          end

          attr_reader :now, :batch_id, :rows, :rollback_plan

          def registration
            rollback_plan.registration
          end

          def rollback_batch_id
            rollback_plan.rollback_batch_id
          end

          def rollback_step_ids
            rollback_plan.rollback_step_ids
          end

          def queued_jobs
            rollback_plan.queued_jobs
          end

          def reason
            rollback_plan.reason
          end
        end
      end
    end
  end
end
