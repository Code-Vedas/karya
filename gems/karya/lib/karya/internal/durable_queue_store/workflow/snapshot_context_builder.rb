# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Reconstructs one durable workflow snapshot with cycle and cache handling.
        class SnapshotContextBuilder
          # Immutable inputs required to rebuild one durable workflow snapshot.
          Request = Struct.new(
            :host,
            :rows,
            :batch_id,
            :now,
            :cache,
            :visiting,
            keyword_init: true
          )

          def initialize(request:)
            @request = request
          end

          def build
            return cache.fetch(normalized_batch_id) if cache.key?(normalized_batch_id)
            raise Workflow::InvalidExecutionError, "child workflow cycle detected at batch #{normalized_batch_id.inspect}" if visiting.key?(normalized_batch_id)

            visiting[normalized_batch_id] = true
            cache[normalized_batch_id] = workflow_snapshot
          ensure
            visiting.delete(normalized_batch_id)
          end

          private

          attr_reader :request

          def host = request.host
          def rows = request.rows
          def batch_id = request.batch_id
          def now = request.now
          def cache = request.cache
          def visiting = request.visiting

          def normalized_batch_id
            @normalized_batch_id ||= Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)
          end

          def workflow_snapshot
            Workflow::Snapshot.new(
              **snapshot_identity,
              batch_id: normalized_batch_id,
              captured_at: now,
              **snapshot_dependencies,
              jobs: SnapshotJobLoader.new(rows:, batch_id: normalized_batch_id, batch:).load,
              **snapshot_policies,
              **snapshot_relationships,
              interactions: host.send(:workflow_interactions, rows, normalized_batch_id),
              **snapshot_interactions
            )
          end

          def snapshot_identity
            {
              workflow_id: registration.workflow_id,
              workflow_family: registration.workflow_family,
              workflow_version: registration.workflow_version
            }
          end

          def snapshot_dependencies
            {
              step_job_ids: registration.step_job_ids,
              dependency_job_ids_by_job_id: registration.dependency_job_ids_by_job_id
            }
          end

          def snapshot_policies
            {
              approval_requirements_by_job_id: registration.approval_requirements_by_job_id,
              approval_decisions_by_job_id: host.send(:workflow_approval_decisions, rows, registration),
              pause_requested_at: host.send(:workflow_pause_requested_at, rows, normalized_batch_id),
              rollback: host.send(:workflow_rollback_snapshot, rows, normalized_batch_id)
            }
          end

          def snapshot_relationships
            {
              child_workflow_ids_by_step_id: registration.child_workflow_ids_by_step_id,
              child_workflows: host.send(:child_workflow_snapshots, rows, normalized_batch_id, now, cache:, visiting:),
              parent: host.send(:workflow_parent_snapshot, rows, normalized_batch_id, now, cache:, visiting:)
            }
          end

          def snapshot_interactions
            {
              interaction_requirements_by_job_id: registration.interaction_requirements_by_job_id,
              interaction_received_at_by_job_id: host.send(:workflow_interaction_received_at_by_job_id, rows, normalized_batch_id, registration)
            }
          end

          def batch
            @batch ||= host.send(:workflow_batch_from_rows, rows, normalized_batch_id)
          end

          def registration
            @registration ||= host.send(:registration_for_batch, rows, normalized_batch_id)
          end
        end
      end
    end
  end
end
