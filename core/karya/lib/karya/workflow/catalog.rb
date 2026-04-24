# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Immutable registry of workflow definitions keyed by workflow id.
    class Catalog
      attr_reader :definitions

      def initialize(definitions:)
        raise InvalidDefinitionError, 'definitions must be an Array of Karya::Workflow::Definition' unless definitions.is_a?(Array)

        @definitions = definitions.each_with_object({}) do |definition, normalized|
          raise InvalidDefinitionError, 'definitions must be Karya::Workflow::Definition instances' unless definition.is_a?(Definition)

          workflow_id = definition.id
          raise InvalidDefinitionError, "duplicate workflow id #{workflow_id.inspect}" if normalized.key?(workflow_id)

          normalized[workflow_id] = definition
        end.freeze
        freeze
      end

      def fetch(workflow_id)
        normalized_workflow_id = Workflow.send(:normalize_identifier, :workflow_id, workflow_id)

        definitions.fetch(normalized_workflow_id)
      end
    end
  end
end
