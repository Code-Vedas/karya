# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Validates that a workflow registration declares support for a requested interaction.
        class InteractionSupportValidator
          def initialize(registration:, interaction_kind:, interaction_name:, batch_id:)
            @registration = registration
            @interaction_kind = interaction_kind
            @interaction_name = interaction_name
            @batch_id = batch_id
          end

          def validate
            return if registration.interaction_supported_keys.key?([interaction_kind, interaction_name])

            raise Workflow::InvalidExecutionError,
                  "workflow batch #{batch_id.inspect} does not support #{interaction_kind} #{interaction_name.inspect}"
          end

          private

          attr_reader :registration, :interaction_kind, :interaction_name, :batch_id
        end
      end
    end
  end
end
