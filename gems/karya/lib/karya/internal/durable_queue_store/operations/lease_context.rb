# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Carries the typed durable lease rows used by lease-backed transitions.
        class LeaseContext
          def initialize(job:, now:, reservation_row:, reservation_token:)
            @job = job
            @now = now
            @reservation_row = reservation_row
            @reservation_token = reservation_token
          end

          attr_reader :job, :now, :reservation_row, :reservation_token
        end
      end
    end
  end
end
