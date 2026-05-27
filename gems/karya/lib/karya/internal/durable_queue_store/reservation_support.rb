# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Shared reservation token sequencing and reservation construction helpers.
      module ReservationSupport
        include SharedSupport

        private

        def next_token
          base_token = normalize_identifier(:token, token_generator.call, error_class: InvalidQueueStoreOperationError)
          @reservation_token_sequence += 1
          "#{base_token}:#{@reservation_token_sequence}"
        end

        def build_reservation(reserved_job:, worker_id:, reserved_at:, lease_duration:)
          reservation_token = next_token
          ensure_unique_reservation_token(reservation_token)

          Reservation.new(
            token: reservation_token,
            job_id: reserved_job.id,
            queue: reserved_job.queue,
            worker_id:,
            reserved_at:,
            expires_at: reserved_at + lease_duration
          )
        end

        def ensure_unique_reservation_token(reservation_token)
          return unless reservation_token_in_use?(reservation_token)

          raise DuplicateReservationTokenError,
                "reservation token #{reservation_token.inspect} is already in use (active or expired)"
        end
      end
    end
  end
end
