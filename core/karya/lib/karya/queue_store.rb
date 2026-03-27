# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'base'

module Karya
  # Raised when enqueue intent conflicts with existing job identity.
  class DuplicateJobError < Error; end

  # Raised when an enqueue operation violates queue store expectations.
  class InvalidEnqueueError < Error; end

  # Raised when a reservation token is unknown to the queue store.
  class UnknownReservationError < Error; end

  # Raised when a reservation token exists but is no longer active.
  class ExpiredReservationError < Error; end

  # Raised when a generated reservation token collides with an active lease.
  class DuplicateReservationTokenError < Error; end

  # Backend-facing contract for queue persistence and reservation behavior.
  module QueueStore
    def enqueue(job:, now:)
      _job = job
      _now = now
      raise NotImplementedError, "#{self.class} must implement ##{__method__}"
    end

    def reserve(queue:, worker_id:, lease_duration:, now:)
      _queue = queue
      _worker_id = worker_id
      _lease_duration = lease_duration
      _now = now
      raise NotImplementedError, "#{self.class} must implement ##{__method__}"
    end

    def release(reservation_token:, now:)
      _reservation_token = reservation_token
      _now = now
      raise NotImplementedError, "#{self.class} must implement ##{__method__}"
    end

    def expire_reservations(now:)
      _now = now
      raise NotImplementedError, "#{self.class} must implement ##{__method__}"
    end
  end
end
