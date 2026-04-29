# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Immutable registry of workflow definitions keyed by workflow id.
    class Catalog
      attr_reader :definitions, :definitions_by_family

      def initialize(definitions:)
        raise InvalidDefinitionError, 'definitions must be an Array of Karya::Workflow::Definition' unless definitions.is_a?(Array)

        @definitions = definitions.each_with_object({}) do |definition, normalized|
          raise InvalidDefinitionError, 'definitions must be Karya::Workflow::Definition instances' unless definition.is_a?(Definition)

          workflow_id = definition.id
          raise InvalidDefinitionError, "duplicate workflow id #{workflow_id.inspect}" if normalized.key?(workflow_id)

          normalized[workflow_id] = definition
        end.freeze
        @definitions_by_family = build_definitions_by_family
        @default_definitions_by_family = build_default_definitions_by_family
        freeze
      end

      def fetch(workflow_id)
        normalized_workflow_id = Workflow.send(:normalize_identifier, :workflow_id, workflow_id)

        definitions.fetch(normalized_workflow_id)
      rescue KeyError => e
        raise InvalidDefinitionError, "workflow #{normalized_workflow_id.inspect} is not registered", cause: e
      end

      def fetch_version(workflow_family:, workflow_version:)
        normalized_family = Workflow.send(:normalize_identifier, :workflow_family, workflow_family)
        normalized_version = Workflow.send(:normalize_identifier, :workflow_version, workflow_version)
        family_inspect = normalized_family.inspect
        family_versions = definitions_by_family.fetch(normalized_family) do
          raise InvalidDefinitionError, "workflow family #{family_inspect} is not registered"
        end

        family_versions.fetch(normalized_version)
      rescue KeyError => e
        raise InvalidDefinitionError,
              "workflow family #{family_inspect} does not include version #{normalized_version.inspect}",
              cause: e
      end

      def resolve(workflow_family:)
        normalized_family = Workflow.send(:normalize_identifier, :workflow_family, workflow_family)
        family_inspect = normalized_family.inspect
        raise InvalidDefinitionError, "workflow family #{family_inspect} is not registered" unless definitions_by_family.key?(normalized_family)

        @default_definitions_by_family.fetch(normalized_family)
      rescue KeyError => e
        raise InvalidDefinitionError, "workflow family #{family_inspect} has no default version", cause: e
      end

      private

      def build_definitions_by_family
        grouped_by_family = definitions.values.group_by(&:workflow_family)
        grouped_by_family.each_with_object({}) do |(workflow_family, family_definitions), grouped|
          grouped[workflow_family] = FamilyDefinitions.new(workflow_family, family_definitions).to_h
        end.freeze
      end

      def build_default_definitions_by_family
        definitions.values.each_with_object({}) do |definition, defaults|
          next unless definition.default_version?

          workflow_family = definition.workflow_family
          raise InvalidDefinitionError, "workflow family #{workflow_family.inspect} declares multiple default versions" if defaults.key?(workflow_family)

          defaults[workflow_family] = definition
        end.freeze
      end

      # Builds version-indexed definitions for one workflow family.
      class FamilyDefinitions
        def initialize(workflow_family, definitions)
          @workflow_family = workflow_family
          @definitions = definitions
        end

        def to_h
          definitions.each_with_object({}) do |definition, grouped|
            workflow_version = definition.workflow_version
            if grouped.key?(workflow_version)
              raise InvalidDefinitionError,
                    "duplicate workflow version #{workflow_version.inspect} for family #{workflow_family.inspect}"
            end

            grouped[workflow_version] = definition
          end.freeze
        end

        private

        attr_reader :definitions, :workflow_family
      end
    end
  end
end
