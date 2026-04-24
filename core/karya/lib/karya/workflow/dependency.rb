# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Immutable dependency edge between two workflow steps.
    class Dependency
      attr_reader :depends_on_step_id, :step_id

      def initialize(step_id:, depends_on_step_id:)
        @step_id = Workflow.send(:normalize_identifier, :step_id, step_id)
        @depends_on_step_id = Workflow.send(:normalize_identifier, :depends_on_step_id, depends_on_step_id)
        freeze
      end
    end
  end
end
