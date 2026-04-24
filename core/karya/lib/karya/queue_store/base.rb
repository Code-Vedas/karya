# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    # Backend-facing contract for durable queue persistence and reservation behavior.
    #
    # Durability contract:
    # - Every successful public method return is an acknowledgment boundary.
    # - `enqueue` is acknowledged only after the queued job is durable and
    #   visible to later `reserve`, `recover_in_flight`, and process takeover.
    # - Durable uniqueness or idempotency checks must be evaluated against
    #   persisted uniqueness state before `enqueue` returns success.
    # - `reserve`, `release`, `start_execution`, `complete_execution`, and
    #   `fail_execution` must each persist their full state transition
    #   atomically before returning.
    # - SQL backends must return after transaction commit. Acknowledged-write
    #   stores such as Redis must return only after the write acknowledgment
    #   that makes the state visible to subsequent commands.
    # - Failed validation, duplicate enqueue, unknown lease, expired lease, and
    #   backend errors must not leave partial queue, lease, execution, retry, or
    #   tombstone state behind.
    #
    # Restart and takeover recovery invariants:
    # - Job identity, queue, handler, arguments, scheduling fields, lifecycle
    #   state, attempt count, created_at, updated_at, retry state, failure
    #   classification, expiration, idempotency_key, uniqueness_key, and
    #   uniqueness_scope must survive process interruption.
    # - Active reservation and execution lease state must survive interruption:
    #   token, job_id, queue, worker_id, reserved_at, and expires_at.
    # - Expired-token tombstones needed to reject stale worker acknowledgments
    #   must survive for the backend's documented tombstone window.
    # - Recovery must be derivable from persisted state alone; in-memory worker
    #   objects, process-local queues, and thread state are never authoritative.
    module Base
      # Enqueue must be atomic and acknowledged only after the canonical queued
      # job state is durable. SQL backends should return after transaction
      # commit; acknowledged-write stores should return after the write
      # acknowledgment that makes the job visible to later reserve and recovery
      # calls. Duplicate id or uniqueness conflicts and invalid enqueue must
      # not mutate existing state.
      def enqueue(job:, now:)
        _job = job
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      # Enqueue a bounded batch atomically. Any invalid job, duplicate job id,
      # duplicate idempotency key, or duplicate uniqueness key must reject the
      # whole batch without making partial writes.
      def enqueue_many(jobs:, now:, batch_id: nil)
        _jobs = jobs
        _now = now
        _batch_id = batch_id
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      # Inspect one durable workflow batch by id. Backends must derive
      # aggregate state from current member job state.
      def batch_snapshot(batch_id:, now:)
        _batch_id = batch_id
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      # Reserve must atomically move one durable queued job to reserved and
      # persist its lease token, worker id, reserved_at, and expires_at before
      # returning the reservation. A returned reservation is the only
      # acknowledgment that the worker owns the lease.
      def reserve(worker_id:, lease_duration:, now:, queue: nil, queues: nil, handler_names: nil)
        _worker_id = worker_id
        _lease_duration = lease_duration
        _now = now
        _queue = queue
        _queues = queues
        _handler_names = handler_names
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      # Release must atomically remove the active reservation lease and durably
      # requeue the job before returning.
      def release(reservation_token:, now:)
        _reservation_token = reservation_token
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      # Start execution must atomically move the job from reserved to running,
      # increment attempt, and persist the active execution lease before the job
      # handler is allowed to run.
      def start_execution(reservation_token:, now:)
        _reservation_token = reservation_token
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      # Complete execution must atomically remove the active execution lease and
      # persist the terminal succeeded state before returning.
      def complete_execution(reservation_token:, now:)
        _reservation_token = reservation_token
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      # Fail execution must atomically remove the active execution lease and
      # persist either failed or retry_pending state before returning.
      def fail_execution(reservation_token:, now:, failure_classification:, retry_policy: nil)
        _reservation_token = reservation_token
        _now = now
        _retry_policy = retry_policy
        _failure_classification = failure_classification
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      # Retry stored failed and retry_pending jobs by moving them back into
      # normal queued execution. Unknown or ineligible jobs must be reported,
      # not inferred through selector state.
      def retry_jobs(job_ids:, now:)
        _job_ids = job_ids
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      # Cancel explicit stored jobs. Active reservation/execution tokens for
      # cancelled work must stop stale worker acknowledgments from succeeding.
      def cancel_jobs(job_ids:, now:)
        _job_ids = job_ids
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def dead_letter_jobs(job_ids:, now:, reason:)
        _job_ids = job_ids
        _now = now
        _reason = reason
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def replay_dead_letter_jobs(job_ids:, now:)
        _job_ids = job_ids
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def retry_dead_letter_jobs(job_ids:, now:, next_retry_at:)
        _job_ids = job_ids
        _now = now
        _next_retry_at = next_retry_at
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def discard_dead_letter_jobs(job_ids:, now:)
        _job_ids = job_ids
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def pause_queue(queue:, now:)
        _queue = queue
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def resume_queue(queue:, now:)
        _queue = queue
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      # Recover expired in-flight leases for a known worker at worker startup or
      # takeover. Backends with liveness metadata may additionally treat leases
      # from a dead worker as orphaned; otherwise recovery is lease-expiry based.
      def recover_orphaned_jobs(worker_id:, now:)
        _worker_id = worker_id
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      # Recover expired reserved/running leases and report what changed.
      #
      # Durable backends must persist job identity, queue, handler, arguments,
      # scheduling fields, lifecycle state, attempt count, retry state,
      # expiration, uniqueness metadata, active reservation/execution lease
      # token, worker id, lease timestamps, and expired-token tombstones. After
      # crash or takeover, every active lease and uniqueness decision must be
      # recoverable from persisted state without relying on process memory.
      def recover_in_flight(now:)
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def expire_reservations(now:)
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def expire_jobs(now:)
        _now = now
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end
    end
  end
end
