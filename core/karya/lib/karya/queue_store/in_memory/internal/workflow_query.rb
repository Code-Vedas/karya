# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        module WorkflowSupport
          # Resolves one explicit workflow query against a workflow snapshot.
          class WorkflowQuery
            def initialize(snapshot:, query:, queried_at:)
              @snapshot = snapshot
              @query = query
              @queried_at = queried_at
            end

            def to_result
              Workflow::QueryResult.new(query:, value:, queried_at:)
            end

            private

            attr_reader :queried_at, :query, :snapshot

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

            def normalized_query
              @normalized_query ||= Workflow.send(:normalize_execution_identifier, :query, query).then do |value|
                raise Workflow::InvalidExecutionError, "unsupported workflow query #{value.inspect}" unless %w[state current-step current-steps].include?(value)

                value
              end
            end

            def current_step_ids
              CurrentSteps.new(snapshot.steps).to_a
            end

            # Resolves the step ids that best represent current workflow progress.
            class CurrentSteps
              def initialize(steps)
                @steps = steps
              end

              def to_a
                active_step_ids = step_ids_for(&:active?)
                return active_step_ids unless active_step_ids.empty?

                step_ids_for(&:ready?)
              end

              private

              attr_reader :steps

              def step_ids_for(&)
                steps.select(&).map(&:step_id).freeze
              end
            end

            private_constant :CurrentSteps
          end
        end
      end
    end
  end
end
