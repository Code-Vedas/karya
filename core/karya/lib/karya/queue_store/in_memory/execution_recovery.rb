# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Rebuilds a running job as queued when execution lease recovery is required.
      class ExecutionRecovery
        def initialize(running_job, now)
          @running_job = running_job
          @now = now
        end

        def to_queued_job
          running_job.transition_to(:queued, updated_at: now)
        end

        private

        attr_reader :now, :running_job
      end
    end
  end
end
