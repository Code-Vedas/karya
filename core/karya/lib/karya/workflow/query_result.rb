# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Immutable result for one explicit workflow query.
    class QueryResult
      SUPPORTED_QUERIES = %w[state current-step current-steps].freeze

      attr_reader :query, :queried_at, :value

      def initialize(query:, value:, queried_at:)
        @query = Query.new(query).to_s
        @value = Value.new(@query, value).normalize
        @queried_at = Timestamp.new(:queried_at, queried_at).to_time
        freeze
      end

      # Normalizes the explicit query name.
      class Query
        def initialize(value)
          @value = value
        end

        def to_s
          normalized_query = Workflow.send(:normalize_execution_identifier, :query, value)
          return normalized_query if SUPPORTED_QUERIES.include?(normalized_query)

          raise InvalidExecutionError, "unsupported workflow query #{normalized_query.inspect}"
        end

        private

        attr_reader :value
      end

      # Validates and freezes query results by query type.
      class Value
        def initialize(query, value)
          @query = query
          @value = value
        end

        def normalize
          case query
          when 'state'
            normalize_state
          when 'current-step'
            normalize_current_step
          when 'current-steps'
            normalize_current_steps
          else
            raise InvalidExecutionError, "unsupported workflow query #{query.inspect}"
          end
        end

        private

        attr_reader :query, :value

        def normalize_state
          raise InvalidExecutionError, 'workflow query "state" must return a Symbol' unless value.is_a?(Symbol)

          value
        end

        def normalize_current_step
          case value
          when NilClass
            nil
          else
            Workflow.send(:normalize_execution_identifier, :step_id, value)
          end
        end

        def normalize_current_steps
          raise InvalidExecutionError, 'workflow query "current-steps" must return an Array' unless value.is_a?(Array)

          value.map do |step_id|
            Workflow.send(:normalize_execution_identifier, :step_id, step_id)
          end.freeze
        end
      end

      # Normalizes timestamps into immutable values.
      class Timestamp
        def initialize(name, value)
          @name = name
          @value = value
        end

        def to_time
          return value.dup.freeze if value.is_a?(Time)

          raise InvalidExecutionError, "#{name} must be a Time"
        end

        private

        attr_reader :name, :value
      end

      private_constant :Query, :SUPPORTED_QUERIES, :Timestamp, :Value
    end
  end
end
