# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        class Reserve < Operation
          # Captures the normalized output of the reserve transition before persistence.
          ReservationOutcome = Struct.new(
            :candidate,
            :reservation,
            :reserved_job,
            :reservation_token_sequence,
            :now,
            keyword_init: true
          )

          # Converts a reserve candidate into a reserved job and active lease.
          class ReservationBuilder
            def initialize(operation:, context:, reserve_request:, candidate:, reservation_token_sequence:)
              @store = operation.store
              @context = context
              @reserve_request = reserve_request
              @candidate = candidate
              @reservation_token_sequence = reservation_token_sequence
            end

            attr_reader :store, :context, :reserve_request, :candidate, :reservation_token_sequence

            def call
              reserved_job = reservable_job.transition_to(
                :reserved,
                updated_at: now,
                failure_classification: nil
              )

              ReservationOutcome.new(
                candidate:,
                reservation: build_reservation(reserved_job),
                reserved_job:,
                reservation_token_sequence:,
                now:
              )
            end

            private

            def now
              reserve_request.fetch(:now)
            end

            def reservable_job
              job = candidate.fetch(:job)
              return job unless job.state == :retry_pending

              job.transition_to(:queued, updated_at: now, next_retry_at: nil, failure_classification: nil)
            end

            def build_reservation(reserved_job)
              token = next_reservation_token
              Reservation.new(
                token:,
                job_id: reserved_job.id,
                queue: reserved_job.queue,
                worker_id: reserve_request.fetch(:worker_id),
                reserved_at: now,
                expires_at: now + reserve_request.fetch(:lease_duration)
              )
            end

            def next_reservation_token
              token = "#{store.send(:token_generator).call}:#{reservation_token_sequence + 1}"
              duplicate = context.rows.fetch(:reservations).any? { |row| row.fetch(:reservation_token) == token }
              raise DuplicateReservationTokenError, "reservation token #{token.inspect} is already in use (active or expired)" if duplicate

              token
            end
          end
        end
      end
    end
  end
end
