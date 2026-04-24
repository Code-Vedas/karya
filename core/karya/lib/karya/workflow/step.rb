# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Immutable one-step workflow composition unit.
    class Step
      attr_reader :arguments, :depends_on, :handler, :id

      def initialize(id:, handler:, arguments: {}, depends_on: nil)
        @id = Workflow.send(:normalize_identifier, :step_id, id)
        @handler = Workflow.send(:normalize_identifier, :handler, handler)
        @arguments = Arguments.new(arguments).normalize
        @depends_on = Dependencies.new(depends_on).normalize
        freeze
      end

      # Normalizes workflow step arguments into the same immutable scalar graph
      # shape used by jobs without coupling workflow code to job internals.
      class Arguments
        IMMUTABLE_SCALAR_CLASSES = [NilClass, Numeric, Symbol, TrueClass, FalseClass].freeze
        DUPLICABLE_SCALAR_CLASSES = [String, Time].freeze

        def initialize(arguments)
          @arguments = arguments
        end

        def normalize
          raise InvalidDefinitionError, 'arguments must be a Hash' unless arguments.is_a?(Hash)

          normalize_hash(arguments, tracker: TraversalTracker.new)
        end

        private

        attr_reader :arguments

        def normalize_hash(value, tracker:)
          tracker.around(value) do
            value.each_with_object({}) do |(key, item), normalized|
              normalized_key = key.to_s.strip
              raise InvalidDefinitionError, 'argument keys must be present' if normalized_key.empty?

              normalized_key = normalized_key.freeze
              if normalized.key?(normalized_key)
                raise InvalidDefinitionError,
                      "duplicate argument key after normalization: #{normalized_key.inspect}"
              end

              normalized[normalized_key] = normalize_value(item, tracker:)
            end.freeze
          end
        end

        def normalize_value(value, tracker:)
          case value
          when Hash
            normalize_hash(value, tracker:)
          when Array
            normalize_array(value, tracker:)
          else
            normalize_scalar(value)
          end
        end

        def normalize_array(value, tracker:)
          tracker.around(value) do
            value.map { |item| normalize_value(item, tracker:) }.freeze
          end
        end

        def normalize_scalar(value)
          arguments_class = self.class
          return value if arguments_class.immutable_scalar?(value)
          return value.dup.freeze if arguments_class.duplicable_scalar?(value)

          raise InvalidDefinitionError,
                'argument values must be composed of Hash, Array, String, Time, Symbol, Numeric, boolean, or nil'
        end

        class << self
          def immutable_scalar?(value)
            IMMUTABLE_SCALAR_CLASSES.any? { |klass| value.is_a?(klass) }
          end

          def duplicable_scalar?(value)
            DUPLICABLE_SCALAR_CLASSES.any? { |klass| value.is_a?(klass) }
          end
        end

        # Detects recursive argument graphs before they recurse forever.
        class TraversalTracker
          def initialize
            @entered_object_ids = {}
          end

          def around(value)
            object_id = value.object_id
            raise InvalidDefinitionError, 'arguments must not contain recursive structures' if entered_object_ids.key?(object_id)

            entered_object_ids[object_id] = true
            yield
          ensure
            entered_object_ids.delete(object_id)
          end

          private

          attr_reader :entered_object_ids
        end

        private_constant :TraversalTracker
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
