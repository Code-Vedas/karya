# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Builds one durable reservation or execution lease record.
      class ReservationRecord
        def initialize(namespace:, reservation:, phase:)
          @namespace = namespace
          @reservation = reservation
          @phase = phase
        end

        def to_h
          {
            namespace:,
            reservation_token: reservation.token,
            job_id: reservation.job_id,
            worker_id: reservation.worker_id,
            phase: phase.to_s,
            reserved_at: reservation.reserved_at,
            lease_expires_at: reservation.expires_at
          }
        end

        private

        attr_reader :namespace, :phase, :reservation
      end
    end
  end
end
