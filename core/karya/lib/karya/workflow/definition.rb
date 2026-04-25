# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Immutable normalized workflow definition built from ordered steps.
    class Definition
      attr_reader :dependencies,
                  :id,
                  :steps

      def initialize(id:, steps:)
        @id = Workflow.send(:normalize_identifier, :workflow_id, id)
        raise InvalidDefinitionError, 'steps must be an Array of Karya::Workflow::Step' unless steps.is_a?(Array)

        graph = Graph.new(steps)
        @steps = graph.steps
        @steps_by_id = @steps.to_h { |workflow_step| [workflow_step.id, workflow_step] }.freeze
        @inspection = graph.inspection
        @dependencies = graph.dependencies
        freeze
      end

      def step_ids = inspection.step_ids

      def root_step_ids = inspection.root_step_ids

      def leaf_step_ids = inspection.leaf_step_ids

      def compensable_step_ids = inspection.compensable_step_ids

      def child_step_ids = inspection.child_step_ids

      def step(step_id)
        normalized_step_id = Workflow.send(:normalize_identifier, :step_id, step_id)
        steps_by_id[normalized_step_id]
      end

      def fetch_step(step_id)
        normalized_step_id = Workflow.send(:normalize_identifier, :step_id, step_id)
        steps_by_id.fetch(normalized_step_id) do
          raise InvalidDefinitionError, "unknown workflow step #{normalized_step_id.inspect}"
        end
      end

      def dependencies_for(step_id)
        workflow_step = fetch_step(step_id)
        inspection.dependencies_by_step_id.fetch(workflow_step.id)
      end

      def dependents_for(step_id)
        workflow_step = fetch_step(step_id)
        inspection.dependents_by_step_id.fetch(workflow_step.id)
      end

      private

      attr_reader :inspection, :steps_by_id

      # Owner-local graph normalizer and validator for workflow step composition.
      class Graph
        attr_reader :dependencies, :inspection, :steps

        def initialize(raw_steps)
          @steps = normalize_steps(raw_steps)
          @steps_by_id = @steps.to_h { |workflow_step| [workflow_step.id, workflow_step] }
          validate_dependency_targets
          validate_acyclic
          @dependencies = DependencyList.new(@steps).dependencies
          @inspection = Inspection.new(@steps)
        end

        private

        attr_reader :steps_by_id

        def normalize_steps(value)
          raise InvalidDefinitionError, 'workflow must define at least one step' if value.empty?

          normalized_steps = value.map do |workflow_step|
            raise InvalidDefinitionError, 'steps must be Karya::Workflow::Step instances' unless workflow_step.is_a?(Step)

            workflow_step
          end

          validate_duplicate_step_ids(normalized_steps)
          normalized_steps.freeze
        end

        def validate_duplicate_step_ids(workflow_steps)
          workflow_steps.group_by(&:id).each do |step_id, grouped_steps|
            raise InvalidDefinitionError, "duplicate step id #{step_id.inspect}" if grouped_steps.length > 1
          end
        end

        def validate_dependency_targets
          steps.each do |workflow_step|
            validate_step_dependencies(workflow_step)
          end
        end

        def validate_step_dependencies(workflow_step)
          step_id = workflow_step.id
          step_id_inspect = step_id.inspect

          workflow_step.depends_on.each do |dependency_id|
            raise InvalidDefinitionError, "step #{step_id_inspect} must not depend on itself" if dependency_id == step_id
            next if steps_by_id.key?(dependency_id)

            raise InvalidDefinitionError,
                  "step #{step_id_inspect} depends on unknown step #{dependency_id.inspect}"
          end
        end

        def validate_acyclic
          visit_states = {}
          steps.each do |workflow_step|
            detect_cycle(workflow_step.id, visit_states)
          end
        end

        def detect_cycle(step_id, visit_states)
          state = visit_states[step_id]
          raise InvalidDefinitionError, "workflow dependency cycle detected at #{step_id.inspect}" if state == :visiting
          return if state == :visited

          visit_states[step_id] = :visiting
          steps_by_id.fetch(step_id).depends_on.each do |dependency_id|
            detect_cycle(dependency_id, visit_states)
          end
          visit_states[step_id] = :visited
        end

        # Builds normalized dependency edge objects from ordered workflow steps.
        class DependencyList
          def initialize(steps)
            @steps = steps
          end

          def dependencies
            steps.each_with_object([]) do |workflow_step, normalized|
              normalized.concat(StepDependencies.new(workflow_step).to_a)
            end.freeze
          end

          private

          attr_reader :steps

          # Builds dependency edge objects for one workflow step.
          class StepDependencies
            def initialize(workflow_step)
              @workflow_step = workflow_step
            end

            def to_a
              step_id = workflow_step.id
              workflow_step.depends_on.map do |dependency_id|
                Dependency.new(step_id:, depends_on_step_id: dependency_id)
              end
            end

            private

            attr_reader :workflow_step
          end

          private_constant :StepDependencies
        end

        # Builds definition inspection indexes from normalized ordered steps.
        class Inspection
          attr_reader :compensable_step_ids,
                      :child_step_ids,
                      :dependencies_by_step_id,
                      :dependents_by_step_id,
                      :leaf_step_ids,
                      :root_step_ids,
                      :step_ids

          def initialize(steps)
            @steps = steps
            @step_ids = steps.map(&:id).freeze
            @dependencies_by_step_id = StepDependencies.new(steps).to_h
            @dependents_by_step_id = StepDependents.new(steps).to_h
            @root_step_ids = StepFilter.new(steps).root_ids
            @leaf_step_ids = StepFilter.new(steps).leaf_ids(@dependents_by_step_id)
            @compensable_step_ids = StepFilter.new(steps).compensable_ids
            @child_step_ids = StepFilter.new(steps).child_ids
            freeze
          end

          private

          attr_reader :steps
        end

        # Builds direct dependency lookup by workflow step id.
        class StepDependencies
          def initialize(steps)
            @steps = steps
          end

          def to_h
            steps.to_h { |workflow_step| StepEntry.new(workflow_step).dependencies_pair }.freeze
          end

          private

          attr_reader :steps
        end

        # Builds reverse dependency lookup by workflow step id.
        class StepDependents
          def initialize(steps)
            @steps = steps
          end

          def to_h
            grouped_pairs = DependencyPairs.new(steps).to_a.group_by(&:first)
            step_ids.to_h do |step_id|
              [step_id, grouped_pairs.fetch(step_id, []).map(&:last).freeze]
            end.freeze
          end

          private

          attr_reader :steps

          def step_ids
            steps.map(&:id)
          end
        end

        # Builds ordered filtered step id lists.
        class StepFilter
          def initialize(steps)
            @steps = steps
          end

          def root_ids
            steps.filter_map { |workflow_step| StepEntry.new(workflow_step).root_id }.freeze
          end

          def leaf_ids(dependents_by_step_id)
            steps.filter_map do |workflow_step|
              StepEntry.new(workflow_step).leaf_id(dependents_by_step_id)
            end.freeze
          end

          def compensable_ids
            steps.filter_map { |workflow_step| StepEntry.new(workflow_step).compensable_id }.freeze
          end

          def child_ids
            steps.filter_map { |workflow_step| StepEntry.new(workflow_step).child_id }.freeze
          end

          private

          attr_reader :steps
        end

        # Builds reverse dependency edge pairs.
        class DependencyPairs
          def initialize(steps)
            @steps = steps
          end

          def to_a
            steps.flat_map { |workflow_step| StepEntry.new(workflow_step).dependent_pairs }
          end

          private

          attr_reader :steps
        end

        # Reads one workflow step for inspection index builders.
        class StepEntry
          def initialize(workflow_step)
            @workflow_step = workflow_step
          end

          def dependencies_pair
            [id, workflow_step.depends_on]
          end

          def dependent_pairs
            workflow_step.depends_on.map { |dependency_id| [dependency_id, id] }
          end

          def root_id
            id if workflow_step.depends_on.empty?
          end

          def leaf_id(dependents_by_step_id)
            id if dependents_by_step_id.fetch(id).empty?
          end

          def compensable_id
            id if workflow_step.compensable?
          end

          def child_id
            id if workflow_step.child_workflow?
          end

          private

          attr_reader :workflow_step

          def id
            workflow_step.id
          end
        end

        private_constant :DependencyList,
                         :DependencyPairs,
                         :Inspection,
                         :StepDependencies,
                         :StepDependents,
                         :StepEntry,
                         :StepFilter
      end

      private_constant :Graph
    end
  end
end
