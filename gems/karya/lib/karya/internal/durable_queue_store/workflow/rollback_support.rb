# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'rollback_batch_identifier'
require_relative 'rollback_eligibility'
require_relative 'rollback_snapshot_eligibility'

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Groups workflow rollback identifier and eligibility helpers.
        module RollbackSupport
          include RollbackBatchIdentifier
          include RollbackEligibility
        end
      end
    end
  end
end
