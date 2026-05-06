# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

module Karya
  module QueueStore
    class Redis
      module Internal
        # Redis-backed synchronization boundary for shared queue-store state.
        class PersistenceMutex
          LOCK_TTL_SECONDS = 5
          LOCK_POLL_INTERVAL = 0.01
          LOCK_ACQUIRE_TIMEOUT_SECONDS = 5.0
          LOCK_MAX_POLL_INTERVAL = 0.25
          LOCK_RENEW_INTERVAL = LOCK_TTL_SECONDS / 2.0
          RELEASE_SCRIPT = <<~LUA
            if redis.call("get", KEYS[1]) == ARGV[1] then
              return redis.call("del", KEYS[1])
            end
            return 0
          LUA
          PERSIST_SCRIPT = <<~LUA
            if redis.call("get", KEYS[1]) == ARGV[1] then
              redis.call("set", KEYS[2], ARGV[2])
              redis.call("expire", KEYS[1], ARGV[3])
              return 1
            end
            return 0
          LUA
          EXTEND_SCRIPT = <<~LUA
            if redis.call("get", KEYS[1]) == ARGV[1] then
              return redis.call("expire", KEYS[1], ARGV[2])
            end
            return 0
          LUA

          # Monotonic deadline helper for bounded Redis lock acquisition.
          class LockAcquisitionDeadline
            def initialize(timeout_seconds)
              @deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
            end

            def expired?
              Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            end

            private

            attr_reader :deadline
          end
          private_constant :LockAcquisitionDeadline

          def initialize(redis:, owner:, state_key:, lock_key:)
            @redis = redis
            @owner = owner
            @state_key = state_key
            @lock_key = lock_key
            @local_mutex = Thread::Mutex.new
            @current_lock_token = nil
            @lock_lost = false
            @lock_loss_cause = nil
          end

          def synchronize(&)
            synchronize_owned_state(persist: true, &)
          end

          def read_only_synchronize(&)
            synchronize_owned_state(persist: false, &)
          end

          private

          attr_reader :lock_key, :local_mutex, :owner, :redis, :state_key

          def synchronize_owned_state(persist:)
            local_mutex.synchronize do
              with_distributed_lock do
                owner.send(:load_persisted_state)
                result = yield
                raise_lock_loss if lock_lost?
                persist_state_if_owned if persist
                result
              end
            end
          end

          def with_distributed_lock
            token = nil
            lock_acquired = false
            renewal_thread = nil
            stop_signal = nil
            token = SecureRandom.uuid
            lock_acquired = acquire_lock?(token)
            reset_lock_loss_state
            @current_lock_token = token
            stop_signal = Queue.new
            renewal_thread = start_lock_renewal(token, stop_signal)

            yield
          ensure
            if renewal_thread
              stop_signal.push(true)
              renewal_thread.join
            end
            @current_lock_token = nil
            release_lock(token) if token && lock_acquired
          end

          def acquire_lock?(token)
            deadline = LockAcquisitionDeadline.new(LOCK_ACQUIRE_TIMEOUT_SECONDS)
            poll_interval = LOCK_POLL_INTERVAL

            until redis.set(lock_key, token, nx: true, ex: LOCK_TTL_SECONDS)
              raise InvalidQueueStoreOperationError, 'timed out acquiring Redis queue-store lock' if deadline.expired?

              Kernel.sleep(poll_interval)
              poll_interval = [poll_interval * 2, LOCK_MAX_POLL_INTERVAL].min
            end

            true
          end

          def start_lock_renewal(token, stop_signal)
            Thread.new do
              loop do
                break if stop_signal.pop(timeout: LOCK_RENEW_INTERVAL)
                next if extend_lock?(token)

                record_lock_loss
                break
              end
            rescue StandardError => e
              record_lock_loss(e)
            end
          end

          def extend_lock?(token)
            redis.eval(EXTEND_SCRIPT, keys: [lock_key], argv: [token, LOCK_TTL_SECONDS.to_s]) == 1
          end

          def release_lock(token)
            redis.eval(RELEASE_SCRIPT, keys: [lock_key], argv: [token])
          rescue StandardError
            nil
          end

          def persist_state_if_owned
            payload = owner.send(:dump_state_payload)
            script_result = redis.eval(
              PERSIST_SCRIPT,
              keys: [lock_key, state_key],
              argv: [@current_lock_token, payload, LOCK_TTL_SECONDS.to_s]
            )
            return payload if script_result == 1

            record_lock_loss
            raise_lock_loss
          rescue InvalidQueueStoreOperationError
            raise
          rescue StandardError => e
            record_lock_loss(e)
            raise_lock_loss
          end

          def record_lock_loss(cause = nil)
            return nil if @lock_lost

            @lock_lost = true
            @lock_loss_cause = cause
            nil
          end

          def reset_lock_loss_state
            @lock_lost = false
            @lock_loss_cause = nil
          end

          def lock_lost?
            @lock_lost
          end

          def verify_lock_still_held
            return if redis.get(lock_key) == @current_lock_token

            record_lock_loss
            raise_lock_loss
          end

          def raise_lock_loss
            raise InvalidQueueStoreOperationError,
                  "lost Redis queue-store lock during mutation#{": #{@lock_loss_cause.message}" if @lock_loss_cause}"
          end
        end
      end
    end
  end
end
