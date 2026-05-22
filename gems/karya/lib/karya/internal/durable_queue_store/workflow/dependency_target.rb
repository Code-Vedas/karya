# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Carries an already-resolved workflow target for dependency evaluation.
        class WorkflowDependencyTarget
          attr_reader :registration, :batch_id

          def initialize(registration:, batch_id:)
            @registration = registration
            @batch_id = batch_id
          end
        end
      end
    end
  end
end
