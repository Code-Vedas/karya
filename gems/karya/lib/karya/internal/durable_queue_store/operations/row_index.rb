# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Indexes durable row groups for repeated job and reservation lookups.
        class RowIndex
          # Wraps one reservation row for typed lookups and job reconstruction.
          class ReservationRow
            def initialize(row:)
              @row = row
            end

            attr_reader :row

            def job_id
              row.fetch(:job_id)
            end

            def worker_id
              row.fetch(:worker_id)
            end

            def reservation_token
              row.fetch(:reservation_token)
            end

            def to_job(jobs_by_id)
              JobRow.new(row: jobs_by_id.fetch(job_id)).to_job
            end
          end

          # Filters reservation rows for one job and an optional worker.
          class ReservationMatcher
            def initialize(job_id:, worker_id:)
              @job_id = job_id
              @worker_matcher = worker_id ? ->(candidate) { candidate == worker_id } : ->(_candidate) { true }
            end

            attr_reader :job_id, :worker_matcher

            def matches_reservation?(row)
              reservation = ReservationRow.new(row:)
              reservation.job_id == job_id && worker_matcher.call(reservation.worker_id)
            end
          end

          def initialize(rows:)
            @rows = rows
          end

          attr_reader :rows

          def jobs_by_id
            @jobs_by_id ||= rows.fetch(:jobs).to_h { |row| [row.fetch(:job_id), row] }
          end

          def queue_entries_for(job_id)
            rows.fetch(:queue_entries).select { |row| row.fetch(:job_id) == job_id }
          end

          def reservations_for(job_id, worker_id: nil)
            matcher = ReservationMatcher.new(job_id:, worker_id:)
            rows.fetch(:reservations).select { |row| matcher.matches_reservation?(row) }
          end

          def reservation_to_job_map
            rows.fetch(:reservations).each_with_object({}) do |reservation_row, jobs|
              reservation = ReservationRow.new(row: reservation_row)
              jobs[reservation.reservation_token] = reservation.to_job(jobs_by_id)
            end
          end
        end
      end
    end
  end
end
