# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

require_relative 'job'
require_relative 'queue_store'
require_relative 'reservation'

module Karya
  # Single-process reference implementation for queue submission and reservation behavior.
  class InMemoryQueueStore
    include QueueStore

    DEFAULT_EXPIRED_TOMBSTONE_LIMIT = 1024

    def initialize(token_generator: -> { SecureRandom.uuid }, expired_tombstone_limit: DEFAULT_EXPIRED_TOMBSTONE_LIMIT)
      valid_tombstone_limit = expired_tombstone_limit.is_a?(Integer) && expired_tombstone_limit >= 0
      raise ArgumentError, 'expired_tombstone_limit must be a finite non-negative Integer' unless valid_tombstone_limit

      @token_generator = token_generator
      @expired_tombstone_limit = expired_tombstone_limit
      @reservation_token_sequence = 0
      @mutex = Mutex.new
      @jobs_by_id = {}
      @queued_job_ids_by_queue = {}
      @reservations_by_token = {}
      @reservation_tokens_in_order = []
      @expired_reservation_tokens = {}
      @expired_reservation_tokens_in_order = []
    end

    def enqueue(job:, now:)
      normalized_now = normalize_time(:now, now)

      @mutex.synchronize do
        expire_reservations_locked(normalized_now)
        validate_enqueue(job)

        job_id = job.id
        raise DuplicateJobError, "job #{job_id.inspect} is already present in the queue store" if @jobs_by_id.key?(job_id)

        queued_job = job.transition_to(:queued, updated_at: normalized_now)
        queued_job_id = queued_job.id
        @jobs_by_id[queued_job_id] = queued_job
        queue_job_ids = (@queued_job_ids_by_queue[queued_job.queue] ||= [])
        queue_job_ids << queued_job_id
        queued_job
      end
    end

    def reserve(queue:, worker_id:, lease_duration:, now:)
      normalized_queue = normalize_identifier(:queue, queue)
      normalized_worker_id = normalize_identifier(:worker_id, worker_id)
      normalized_now = normalize_time(:now, now)
      normalized_lease_duration = lease_duration
      invalid_lease_duration = !normalized_lease_duration.is_a?(Numeric) ||
                               !normalized_lease_duration.positive? ||
                               !normalized_lease_duration.finite?
      raise InvalidEnqueueError, 'lease_duration must be a positive number' if invalid_lease_duration

      @mutex.synchronize do
        expire_reservations_locked(normalized_now)

        queue_job_ids = @queued_job_ids_by_queue.fetch(normalized_queue, [])
        job_id = queue_job_ids.first
        return nil unless job_id

        queued_job = @jobs_by_id.fetch(job_id)
        reserved_job = queued_job.transition_to(:reserved, updated_at: normalized_now)
        reserved_job_id = reserved_job.id
        reservation = build_reservation(
          reserved_job:,
          worker_id: normalized_worker_id,
          reserved_at: normalized_now,
          lease_duration: normalized_lease_duration
        )
        reservation_token = reservation.token

        queue_job_ids.shift
        @queued_job_ids_by_queue.delete(normalized_queue) if queue_job_ids.empty?
        @jobs_by_id[reserved_job_id] = reserved_job
        @reservations_by_token[reservation_token] = reservation
        @reservation_tokens_in_order << reservation_token
        reservation
      end
    end

    def release(reservation_token:, now:)
      normalized_token = normalize_identifier(:reservation_token, reservation_token)
      normalized_now = normalize_time(:now, now)

      @mutex.synchronize do
        reservation = @reservations_by_token[normalized_token]
        reservation_label = normalized_token.inspect
        raise_expired_reservation_error(normalized_token, reservation_label) unless reservation
        raise UnknownReservationError, "reservation #{reservation_label} is not active" unless reservation

        if reservation.expired?(normalized_now)
          requeue_expired_reservation(reservation, normalized_now)
          raise ExpiredReservationError, "reservation #{reservation_label} has expired"
        end

        requeue_reservation(reservation, normalized_now)
      end
    end

    def expire_reservations(now:)
      normalized_now = normalize_time(:now, now)

      @mutex.synchronize do
        expire_reservations_locked(normalized_now)
      end
    end

    private

    attr_reader :token_generator

    def validate_enqueue(job)
      raise InvalidEnqueueError, 'job must be a Karya::Job' unless job.is_a?(Job)
      raise InvalidEnqueueError, 'job must be in :submission state before enqueue' unless job.state == :submission
    end

    def next_token
      base_token = normalize_identifier(:token, token_generator.call)
      @reservation_token_sequence += 1
      "#{base_token}:#{@reservation_token_sequence}"
    end

    def expire_reservations_locked(now)
      expired_reservations = @reservation_tokens_in_order.filter_map do |token|
        reservation = @reservations_by_token.fetch(token)
        expired = reservation.expired?(now)
        reservation if expired
      end

      expired_reservations.map do |reservation|
        requeue_expired_reservation(reservation, now)
      end
    end

    def requeue_reservation(reservation, now)
      reservation_token = reservation.token
      @reservations_by_token.delete(reservation_token)
      remove_reservation_token(reservation_token)

      reserved_job = @jobs_by_id.fetch(reservation.job_id)
      queued_job = reserved_job.transition_to(:queued, updated_at: now)
      queued_job_id = queued_job.id
      @jobs_by_id[queued_job_id] = queued_job
      queue_job_ids = (@queued_job_ids_by_queue[queued_job.queue] ||= [])
      queue_job_ids << queued_job_id
      queued_job
    end

    def requeue_expired_reservation(reservation, now)
      queued_job = requeue_reservation(reservation, now)
      remember_expired_reservation_token(reservation.token)
      queued_job
    end

    def normalize_identifier(name, value)
      normalized_value = value.to_s.strip
      raise InvalidEnqueueError, "#{name} must be present" if normalized_value.empty?

      normalized_value
    end

    def normalize_time(name, value)
      return value if value.is_a?(Time)

      raise InvalidEnqueueError, "#{name} must be a Time"
    end

    def remove_reservation_token(reservation_token)
      reservation_index = @reservation_tokens_in_order.index(reservation_token)
      @reservation_tokens_in_order.delete_at(reservation_index) if reservation_index
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
      return unless @reservations_by_token.key?(reservation_token) || @expired_reservation_tokens.key?(reservation_token)

      raise DuplicateReservationTokenError,
            "reservation token #{reservation_token.inspect} is already in use (active or expired)"
    end

    def raise_expired_reservation_error(reservation_token, reservation_label)
      return unless @expired_reservation_tokens.key?(reservation_token)

      raise ExpiredReservationError, "reservation #{reservation_label} has expired"
    end

    def remember_expired_reservation_token(reservation_token)
      return if @expired_reservation_tokens.key?(reservation_token)

      @expired_reservation_tokens[reservation_token] = true
      @expired_reservation_tokens_in_order << reservation_token
      prune_expired_reservation_tokens
    end

    def prune_expired_reservation_tokens
      while @expired_reservation_tokens_in_order.length > @expired_tombstone_limit
        oldest_token = @expired_reservation_tokens_in_order.shift
        @expired_reservation_tokens.delete(oldest_token)
      end
    end
  end
end
