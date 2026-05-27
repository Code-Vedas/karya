# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module WorkflowRuntimeSupport
        # Carries stable workflow snapshot inputs for child snapshot builders.
        class ChildWorkflowSnapshotContext
          attr_reader :host, :rows, :now, :cache, :visiting

          def initialize(host:, rows:, now:, cache:, visiting:)
            @host = host
            @rows = rows
            @now = now
            @cache = cache
            @visiting = visiting
          end
        end
      end
    end
  end
end
