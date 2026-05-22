# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Builds the supported interaction key set for a workflow registration.
        class InteractionSupportedKeysBuilder
          def initialize(approval_requirements_by_job_id:, interaction_requirements_by_job_id:)
            @approval_requirements_by_job_id = approval_requirements_by_job_id
            @interaction_requirements_by_job_id = interaction_requirements_by_job_id
          end

          def to_h
            interaction_keys.tap do |keys|
              approval_requirements_by_job_id.each_value do |requirement|
                keys[[:signal, requirement_value(requirement, :name)]] = true
              end
            end.freeze
          end

          private

          attr_reader :approval_requirements_by_job_id, :interaction_requirements_by_job_id

          def interaction_keys
            interaction_requirements_by_job_id.values.to_h do |requirement|
              [[requirement_value(requirement, :kind).to_sym, requirement_value(requirement, :name)], true]
            end
          end

          def requirement_value(requirement, key)
            requirement[key] || requirement.fetch(key.to_s)
          end
        end
      end
    end
  end
end
