# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Applies recovery jobs and stuck-job metadata to one snapshot row set.
        class RecoveredSnapshotRowsBuilder
          def initialize(rows:, recovery:, now:)
            @rows = rows
            @recovery = recovery
            @now = now
          end

          attr_reader :rows, :recovery, :now

          def build
            StuckJobRecoveryMerger.new(
              rows: recovered_rows,
              recovered_running_jobs: recovery.fetch(:recovered_running_jobs),
              now:
            ).merge
          end

          private

          def recovered_rows
            RecoveredRowsApplier.new(
              namespace: rows.fetch(:namespace),
              rows:,
              jobs: recovery_jobs
            ).apply
          end

          def recovery_jobs
            recovery.values_at(:expired_jobs, :recovered_reserved_jobs, :recovered_running_jobs).flatten
          end
        end
      end
    end
  end
end
