# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Builds nested child workflow snapshots and resolves workflow state for one batch.
        class WorkflowChildState
          def initialize(state:, now:, cache: {}, visiting: {})
            @store_state = state
            @now = now
            @cache = cache
            @visiting = visiting
          end

          def resolve(batch_id)
            return cache.fetch(batch_id) if cache.key?(batch_id)
            raise Workflow::InvalidExecutionError, "child workflow cycle detected at batch #{batch_id.inspect}" if visiting.key?(batch_id)

            added_to_visiting = false
            visiting[batch_id] = true
            added_to_visiting = true
            cache[batch_id] = StateSnapshot.new(batch_id:, state: store_state, now:, cache:, visiting:).state
          ensure
            visiting.delete(batch_id) if added_to_visiting
          end

          # Recursively builds one workflow snapshot state using registered child relationships.
          class StateSnapshot
            def initialize(batch_id:, state:, now:, cache:, visiting:)
              @batch_id = batch_id
              @store_state = state
              @now = now
              @cache = cache
              @visiting = visiting
            end

            def state
              Workflow::Snapshot.new(
                workflow_id: registration.workflow_id,
                batch_id:,
                captured_at: now,
                step_job_ids: registration.step_job_ids,
                dependency_job_ids_by_job_id: registration.dependency_job_ids_by_job_id,
                jobs:,
                child_workflow_ids_by_step_id: registration.child_workflow_ids_by_step_id,
                child_workflows:
              ).state
            end

            private

            attr_reader :batch_id, :cache, :now, :store_state, :visiting

            def batch
              @batch ||= store_state.batches_by_id.fetch(batch_id)
            end

            def registration
              @registration ||= store_state.workflow_registrations_by_batch_id.fetch(batch_id)
            end

            def jobs
              @jobs ||= batch.job_ids.map { |job_id| store_state.jobs_by_id.fetch(job_id) }
            end

            def child_workflows
              store_state.workflow_children.for_parent_batch(batch_id).map do |relationship|
                RelationshipSnapshot.new(relationship:, store_state:, now:, cache:, visiting:).to_snapshot
              end.freeze
            end

            # Builds one nested child workflow snapshot from stored relationship metadata.
            class RelationshipSnapshot
              def initialize(relationship:, store_state:, now:, cache:, visiting:)
                @relationship = relationship
                @store_state = store_state
                @now = now
                @cache = cache
                @visiting = visiting
              end

              def to_snapshot
                Workflow::ChildWorkflowSnapshot.new(
                  parent_workflow_id: relationship.parent_workflow_id,
                  parent_batch_id: relationship.parent_batch_id,
                  parent_step_id: relationship.parent_step_id,
                  parent_job_id: relationship.parent_job_id,
                  child_workflow_id: relationship.child_workflow_id,
                  child_batch_id: child_batch_id,
                  child_state: child_state
                )
              end

              private

              attr_reader :cache, :now, :relationship, :store_state, :visiting

              def child_batch_id
                relationship.child_batch_id
              end

              def child_state
                WorkflowChildState.new(state: store_state, now:, cache:, visiting:).resolve(child_batch_id)
              end
            end

            private_constant :RelationshipSnapshot
          end

          private_constant :StateSnapshot

          private

          attr_reader :cache, :now, :store_state, :visiting
        end
      end
    end
  end
end
