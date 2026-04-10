# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Reservation request normalization and token construction helpers.
      module RequestSupport
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
          return unless state.reservation_token_in_use?(reservation_token)

          raise DuplicateReservationTokenError,
                "reservation token #{reservation_token.inspect} is already in use (active or expired)"
        end

        def normalize_reserve_queues(queue:, queues:)
          reserve_queues = queue && queues ? nil : queue || queues
          raise InvalidQueueStoreOperationError, RESERVE_QUEUES_ERROR_MESSAGE unless reserve_queues

          Primitives::QueueList.new(reserve_queues, error_class: InvalidQueueStoreOperationError).normalize
        end

        def normalize_reserve_request(worker_id:, lease_duration:, now:, queue:, queues:, handler_names:)
          {
            handler_matcher: HandlerMatcher.new(handler_names),
            lease_duration: LeaseDuration.new(lease_duration).normalize,
            now: normalize_time(:now, now, error_class: InvalidQueueStoreOperationError),
            queues: normalize_reserve_queues(queue:, queues:),
            worker_id: normalize_identifier(:worker_id, worker_id, error_class: InvalidQueueStoreOperationError)
          }
        end
      end
    end
  end
end
