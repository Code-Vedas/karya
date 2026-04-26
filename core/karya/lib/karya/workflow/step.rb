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
      attr_reader :arguments,
                  :child_workflow,
                  :compensate_with,
                  :compensation_arguments,
                  :depends_on,
                  :handler,
                  :id,
                  :wait_for_event,
                  :wait_for_signal

      def initialize(id:, handler:, **options)
        @id = Workflow.send(:normalize_identifier, :step_id, id)
        @handler = Workflow.send(:normalize_identifier, :handler, handler)
        normalized_options = Options.new(options)
        @arguments = Arguments.new(normalized_options.arguments, step_id: @id, handler: @handler).normalize
        @depends_on = Dependencies.new(normalized_options.depends_on).normalize
        @child_workflow = ChildWorkflow.new(normalized_options.child_workflow).normalize
        @compensate_with = CompensationHandler.new(normalized_options.compensate_with).normalize
        @compensation_arguments = Arguments.new(
          normalized_options.compensation_arguments,
          step_id: @id,
          handler: compensation_handler_label
        ).normalize
        @wait_for_signal = InteractionName.new(:wait_for_signal, normalized_options.wait_for_signal).normalize
        @wait_for_event = InteractionName.new(:wait_for_event, normalized_options.wait_for_event).normalize
        validate_compensation_configuration
        validate_interaction_configuration
        freeze
      end

      def compensable?
        !!compensate_with
      end

      def child_workflow?
        !!child_workflow
      end

      # Centralizes optional constructor field defaults and key validation.
      class Options
        ALLOWED_KEYS = %i[
          arguments
          depends_on
          compensate_with
          compensation_arguments
          child_workflow
          wait_for_signal
          wait_for_event
        ].freeze

        def initialize(options)
          @options = options
          validate_keys
        end

        def arguments
          options.fetch(:arguments, {})
        end

        def depends_on
          options.fetch(:depends_on, nil)
        end

        def compensate_with
          options.fetch(:compensate_with, nil)
        end

        def child_workflow
          options.fetch(:child_workflow, nil)
        end

        def compensation_arguments
          options.fetch(:compensation_arguments, {})
        end

        def wait_for_signal
          options.fetch(:wait_for_signal, nil)
        end

        def wait_for_event
          options.fetch(:wait_for_event, nil)
        end

        private

        attr_reader :options

        def validate_keys
          return if unexpected_keys.empty?

          raise ArgumentError, "#{unknown_keyword_label}: #{formatted_unexpected_keys}"
        end

        def unexpected_keys
          options.keys - ALLOWED_KEYS
        end

        def unknown_keyword_label
          unexpected_keys.length == 1 ? 'unknown keyword' : 'unknown keywords'
        end

        def formatted_unexpected_keys
          unexpected_keys.map { |key| ":#{key}" }.join(', ')
        end
      end

      # Normalizes an optional child workflow id.
      class ChildWorkflow
        def initialize(value)
          @value = value
        end

        def normalize
          case value
          when NilClass
            nil
          else
            Workflow.send(:normalize_identifier, :child_workflow, value)
          end
        end

        private

        attr_reader :value
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

      # Normalizes an optional compensation handler.
      class CompensationHandler
        def initialize(value)
          @value = value
        end

        def normalize
          case value
          when NilClass
            nil
          else
            Workflow.send(:normalize_identifier, :compensate_with, value)
          end
        end

        private

        attr_reader :value
      end

      # Normalizes one optional interaction gate name.
      class InteractionName
        def initialize(field_name, value)
          @field_name = field_name
          @value = value
        end

        def normalize
          case value
          when NilClass
            nil
          else
            Workflow.send(:normalize_identifier, field_name, value)
          end
        end

        private

        attr_reader :field_name, :value
      end

      private_constant :Arguments, :ChildWorkflow, :CompensationHandler, :Dependencies, :InteractionName, :Options

      private

      def validate_compensation_configuration
        return if compensate_with || compensation_arguments.empty?

        raise InvalidDefinitionError, "workflow step #{id.inspect} cannot define compensation_arguments without compensate_with"
      end

      def validate_interaction_configuration
        return unless wait_for_signal && wait_for_event

        raise InvalidDefinitionError, "workflow step #{id.inspect} cannot wait for both signal and event"
      end

      def compensation_handler_label
        compensate_with || 'compensation'
      end
    end
  end
end
