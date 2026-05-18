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
          PERSIST_SNAPSHOT_SCRIPT = <<~LUA
            if redis.call("get", KEYS[1]) == ARGV[1] then
              local version = redis.call("incr", KEYS[2])
              redis.call("set", KEYS[3], ARGV[2])
              redis.call("expire", KEYS[1], ARGV[3])
              return version
            end
            return 0
          LUA
          APPEND_EVENT_SCRIPT = <<~LUA
            if redis.call("get", KEYS[1]) == ARGV[1] then
              local version = redis.call("incr", KEYS[2])
              redis.call("set", ARGV[2] .. version, ARGV[3])
              redis.call("expire", KEYS[1], ARGV[4])
              return version
            end
            return 0
          LUA
          COMPACT_SNAPSHOT_SCRIPT = <<~LUA
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

          def initialize(redis:, owner:, state_key:, lock_key:, version_key:)
            @redis = redis
            @owner = owner
            @state_key = state_key
            @lock_key = lock_key
            @version_key = version_key
            @local_mutex = Thread::Mutex.new
            @current_lock_token = nil
            @lock_lost = false
            @lock_loss_cause = nil
          end

          def synchronize(persist_if: nil, &)
            synchronize_owned_state(mode: :snapshot, persist_if:, &)
          end

          def synchronize_with_event(event_builder:, persist_if: nil, &)
            synchronize_owned_state(mode: :event, event_builder:, persist_if:, &)
          end

          def read_only_synchronize(&)
            synchronize_owned_state(mode: :read_only, &)
          end

          def compact_snapshot(payload:)
            redis.eval(
              COMPACT_SNAPSHOT_SCRIPT,
              keys: [lock_key, state_key],
              argv: [@current_lock_token, payload, LOCK_TTL_SECONDS.to_s]
            ) == 1
          rescue StandardError
            false
          end

          private

          attr_reader :lock_key, :local_mutex, :owner, :redis, :state_key, :version_key

          def synchronize_owned_state(mode:, event_builder: nil, persist_if: nil)
            event_mode = mode == :event

            local_mutex.synchronize do
              with_distributed_lock do
                owner.send(:load_persisted_state)
                result = yield
                raise_lock_loss if lock_lost?
                verify_lock_still_held
                persist_if_owned(mode:, event_builder:, persist_if:, result:)
                result
              rescue ExpiredReservationError
                unless event_mode
                  restore_owner_state_after_failure
                  raise
                end

                raise_lock_loss if lock_lost?
                verify_lock_still_held
                begin
                  persist_snapshot_if_owned
                rescue StandardError
                  restore_owner_state_after_failure
                  raise
                end
                raise
              rescue StandardError
                restore_owner_state_after_failure
                raise
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
                begin
                  break if stop_signal.pop(timeout: LOCK_RENEW_INTERVAL)
                rescue ThreadError
                  nil
                end
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

          def persist_if_owned(mode:, event_builder:, persist_if:, result:)
            return nil if persist_if && !persist_if.call(result)

            case mode
            when :read_only
              nil
            when :snapshot
              persist_snapshot_if_owned
            when :event
              persist_event_if_owned(event_builder.call(result))
            else
              raise InvalidQueueStoreOperationError, "unsupported Redis persistence mode: #{mode.inspect}"
            end
          end

          def persist_snapshot_if_owned
            current_version = redis.get(version_key)
            next_version = current_version ? Integer(current_version, 10) + 1 : 1
            payload = owner.send(:dump_state_payload, applied_version: next_version)
            script_result = redis.eval(
              PERSIST_SNAPSHOT_SCRIPT,
              keys: [lock_key, version_key, state_key],
              argv: [@current_lock_token, payload, LOCK_TTL_SECONDS.to_s]
            )
            return owner.send(:snapshot_persisted, script_result) if script_result.is_a?(Integer) && script_result.positive?

            record_lock_loss
            raise_lock_loss
          rescue InvalidQueueStoreOperationError
            raise
          rescue StandardError => e
            record_lock_loss(e)
            raise_lock_loss
          end

          def persist_event_if_owned(event)
            payload = owner.send(:dump_event_payload, event)
            script_result = redis.eval(
              APPEND_EVENT_SCRIPT,
              keys: [lock_key, version_key],
              argv: [@current_lock_token, event_key_prefix, payload, LOCK_TTL_SECONDS.to_s]
            )
            return owner.send(:event_persisted, script_result) if script_result.is_a?(Integer) && script_result.positive?

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

          def event_key_prefix
            "#{owner.send(:namespace)}:queue_store:event:"
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

          def restore_owner_state_after_failure
            owner.send(:restore_authoritative_state_after_failure)
            nil
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
