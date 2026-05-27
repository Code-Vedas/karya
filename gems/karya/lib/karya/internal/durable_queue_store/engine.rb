# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Adapter-facing entrypoint for row-native persisted operations.
      class Engine
        READ_ONLY_OPERATIONS = %i[uniqueness_decision uniqueness_snapshot].freeze
        RESERVE_OPERATIONS = %i[reserve].freeze
        OPERATION_CLASS_NAMES = {
          enqueue: :Enqueue,
          enqueue_many: :EnqueueMany,
          reserve: :Reserve,
          release: :Release,
          start_execution: :StartExecution,
          complete_execution: :CompleteExecution,
          fail_execution: :FailExecution,
          retry_jobs: :RetryJobs,
          cancel_jobs: :CancelJobs,
          dead_letter_jobs: :DeadLetterJobs,
          replay_dead_letter_jobs: :ReplayDeadLetterJobs,
          retry_dead_letter_jobs: :RetryDeadLetterJobs,
          discard_dead_letter_jobs: :DiscardDeadLetterJobs,
          pause_queue: :PauseQueue,
          resume_queue: :ResumeQueue,
          batch_snapshot: :BatchSnapshot,
          backpressure_snapshot: :BackpressureSnapshot,
          reliability_snapshot: :ReliabilitySnapshot,
          uniqueness_decision: :UniquenessDecision,
          uniqueness_snapshot: :UniquenessSnapshot,
          recover_orphaned_jobs: :RecoverOrphanedJobs,
          recover_in_flight: :RecoverInFlight,
          expire_reservations: :ExpireReservations,
          expire_jobs: :ExpireJobs,
          enqueue_workflow: :EnqueueWorkflow,
          workflow_snapshot: :WorkflowSnapshot,
          workflow_history: :WorkflowHistory,
          query_workflow: :QueryWorkflow,
          deliver_workflow_signal: :DeliverWorkflowSignal,
          deliver_workflow_event: :DeliverWorkflowEvent,
          pause_workflow: :PauseWorkflow,
          resume_workflow: :ResumeWorkflow,
          approve_workflow_checkpoints: :ApproveWorkflowCheckpoints,
          reject_workflow_checkpoints: :RejectWorkflowCheckpoints,
          enqueue_child_workflow: :EnqueueChildWorkflow,
          sync_child_workflows: :SyncChildWorkflows,
          rollback_workflow: :RollbackWorkflow,
          retry_workflow_steps: :RetryWorkflowSteps,
          dead_letter_workflow_steps: :DeadLetterWorkflowSteps,
          replay_workflow_steps: :ReplayWorkflowSteps,
          retry_dead_letter_workflow_steps: :RetryDeadLetterWorkflowSteps,
          discard_workflow_steps: :DiscardWorkflowSteps
        }.freeze

        def initialize(store:)
          @store = store
        end

        def execute(operation_name:, request:)
          operation = build_operation(operation_name, request)
          context = operation_context(operation_name, request)
          result = operation.call(context:)
          return result unless result.is_a?(OperationResult)

          persist_result(result, context)
          result.value
        end

        private

        attr_reader :store

        def build_operation(operation_name, request)
          operation_class_name = OPERATION_CLASS_NAMES.fetch(operation_name)
          Operations.const_get(operation_class_name, false).new(
            operation_name:,
            store:,
            request:
          )
        end

        def operation_context(operation_name, request)
          runner_for(operation_name).call do
            durable_state_store = store.send(:durable_state_store)
            namespace = store.namespace
            metadata = durable_state_store.fetch_metadata(namespace:)
            rows = durable_state_store.fetch_rows_for_operation(
              operation_name:,
              namespace:,
              request:
            )
            durable_state_store.lock_rows_for_operation(
              operation_name:,
              namespace:,
              request:,
              metadata:,
              rows:
            )
            OperationContext.new(namespace:, request:, metadata:, rows:)
          end
        end

        def runner_for(operation_name)
          persistence_mutex = store.persistence_mutex
          if READ_ONLY_OPERATIONS.include?(operation_name)
            ->(&block) { persistence_mutex.run_read_only(operation_name:, &block) }
          elsif RESERVE_OPERATIONS.include?(operation_name)
            ->(&block) { persistence_mutex.run_reserve(operation_name:, &block) }
          else
            ->(&block) { persistence_mutex.run_mutation(operation_name:, &block) }
          end
        end

        def persist_result(result, context)
          return unless result.persist?

          mutation_plan = result.mutation_plan
          return if mutation_plan.empty?

          store.send(:durable_state_store).apply_mutation_plan(
            plan: mutation_plan,
            namespace: context.namespace
          )
        end
      end
    end
  end
end
