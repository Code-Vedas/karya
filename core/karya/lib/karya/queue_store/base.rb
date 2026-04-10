# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    # Backend-facing contract for queue persistence and reservation behavior.
    module Base
      def enqueue(job:, now:)
        _job = job
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def reserve(worker_id:, lease_duration:, now:, queue: nil, queues: nil, handler_names: nil)
        _worker_id = worker_id
        _lease_duration = lease_duration
        _now = now
        _queue = queue
        _queues = queues
        _handler_names = handler_names
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def release(reservation_token:, now:)
        _reservation_token = reservation_token
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def start_execution(reservation_token:, now:)
        _reservation_token = reservation_token
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def complete_execution(reservation_token:, now:)
        _reservation_token = reservation_token
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def fail_execution(reservation_token:, now:, retry_policy: nil)
        _reservation_token = reservation_token
        _now = now
        _retry_policy = retry_policy
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def expire_reservations(now:)
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end
    end
  end
end
