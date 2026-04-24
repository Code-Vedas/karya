# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../internal/immutable_argument_graph'

module Karya
  module Workflow
    # Immutable one-step workflow composition unit.
    class Step
      attr_reader :arguments, :depends_on, :handler, :id

      def initialize(id:, handler:, arguments: {}, depends_on: nil)
        @id = Workflow.send(:normalize_identifier, :step_id, id)
        @handler = Workflow.send(:normalize_identifier, :handler, handler)
        @arguments = Arguments.new(arguments, step_id: @id, handler: @handler).normalize
        @depends_on = Dependencies.new(depends_on).normalize
        freeze
      end

      # Normalizes workflow step arguments into the same immutable scalar graph
      # shape used by jobs without coupling workflow code to job internals.
      class Arguments
        def initialize(arguments, step_id:, handler:)
          @arguments = arguments
          @step_id = step_id
          @handler = handler
        end

        def normalize
          Internal::ImmutableArgumentGraph.new(arguments, error_class: InvalidDefinitionError).normalize
        rescue InvalidDefinitionError => e
          raise InvalidDefinitionError, "#{context_message}: #{e.message}", cause: e
        end

        private

        attr_reader :arguments, :handler, :step_id

        def context_message
          "workflow step #{step_id.inspect} (handler #{handler.inspect}) has invalid arguments"
        end
      end

      # Normalizes one step's prerequisite list into frozen normalized ids.
      class Dependencies
        def initialize(value)
          @value = value
        end

        def normalize
          normalized_dependencies = raw_dependencies.map do |dependency_id|
            Workflow.send(:normalize_identifier, :depends_on, dependency_id)
          end
          duplicate_dependency = normalized_dependencies.tally.find { |_dependency_id, count| count > 1 }&.first
          raise InvalidDefinitionError, "duplicate depends_on step #{duplicate_dependency.inspect} after normalization" if duplicate_dependency

          normalized_dependencies.freeze
        end

        private

        attr_reader :value

        def raw_dependencies
          value.is_a?(Array) ? value : [value].compact
        end
      end

      private_constant :Arguments, :Dependencies
    end
  end
end
