# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'current_step_selector'
require_relative 'query_builder'
require_relative 'snapshot_job_loader'
require_relative 'snapshot_context_builder'

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Reconstructs workflow snapshots and query results from durable rows.
        module SnapshotBuilder
          private

          def build_workflow_snapshot(rows:, batch_id:, now:, cache: {}, visiting: {})
            SnapshotContextBuilder.new(
              request: SnapshotContextBuilder::Request.new(
                host: self,
                rows:,
                batch_id:,
                now:,
                cache:,
                visiting:
              )
            ).build
          end

          def workflow_query_result(snapshot:, query:, queried_at:)
            QueryBuilder.new(snapshot:, query:, queried_at:).build
          end

          def workflow_query_value(snapshot, query)
            QueryBuilder.new(snapshot:, query:, queried_at: Time.at(0)).value
          end

          def current_workflow_step_ids(steps)
            CurrentStepSelector.new(steps:).call
          end

          def workflow_state_for_batch(rows, batch_id, now, cache:, visiting:)
            build_workflow_snapshot(rows:, batch_id:, now:, cache:, visiting:).state
          end

          def workflow_snapshot_jobs(rows, batch_id, batch)
            SnapshotJobLoader.new(rows:, batch_id:, batch:).load
          end
        end
      end
    end
  end
end
