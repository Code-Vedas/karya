# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Applies expired and recovered jobs back onto normalized durable rows.
        class RecoveredRowsApplier
          def initialize(namespace:, rows:, jobs:)
            @namespace = namespace
            @rows = rows
            @jobs = jobs
          end

          attr_reader :namespace, :rows, :jobs

          def apply
            jobs.reduce(rows) do |updated_rows, job|
              JobRuntimeRows.new(namespace:, rows: updated_rows).replace(job_id: job.id, replacement_job: job)
            end
          end
        end
      end
    end
  end
end
