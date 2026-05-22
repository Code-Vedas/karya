# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Builds workflow query values and query results from a workflow snapshot.
        class QueryBuilder
          def initialize(snapshot:, query:, queried_at:)
            @snapshot = snapshot
            @query = query
            @queried_at = queried_at
          end

          def build
            Workflow::QueryResult.new(
              query:,
              value: value,
              queried_at:
            )
          end

          def value
            case normalized_query
            when 'state'
              snapshot.state
            when 'current-step'
              current_step_ids.first
            when 'current-steps'
              current_step_ids
            else
              raise Workflow::InvalidExecutionError, "unsupported workflow query #{normalized_query.inspect}"
            end
          end

          private

          attr_reader :snapshot, :query, :queried_at

          def normalized_query
            @normalized_query ||= Workflow.send(:normalize_execution_identifier, :query, query)
          end

          def current_step_ids
            @current_step_ids ||= CurrentStepSelector.new(steps: snapshot.steps).call
          end
        end
      end
    end
  end
end
