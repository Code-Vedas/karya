# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Builds deterministic rollback batch identifiers for workflow rollback runs.
        module RollbackBatchIdentifier
          private

          def rollback_batch_id_for(batch_id)
            "#{ROLLBACK_BATCH_PREFIX}#{batch_id.unpack1('H*')}".freeze
          end
        end
      end
    end
  end
end
