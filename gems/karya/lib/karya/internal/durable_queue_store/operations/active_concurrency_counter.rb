# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Counts active reservations that consume one concurrency scope.
        class ActiveConcurrencyCounter
          def initialize(rows:, scope_key:)
            @rows = rows
            @scope_key = scope_key
          end

          attr_reader :rows, :scope_key

          def count
            reservations.count do |reservation_row|
              scoped_job?(reservation_row)
            end
          end

          private

          def reservations
            rows.fetch(:reservations)
          end

          def scoped_job?(reservation_row)
            job = runtime_rows.job_for(RowIndex::ReservationRow.new(row: reservation_row).job_id)
            ScopeKeySet.new(job:, explicit_scope: job.concurrency_scope).to_a.include?(scope_key)
          end

          def runtime_rows
            @runtime_rows ||= JobRuntimeRows.new(namespace: rows[:namespace].to_s, rows:)
          end
        end
      end
    end
  end
end
