# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

module Karya
  module QueueStore
    class Redis < InMemory
      module Internal
        # Redis-backed synchronization boundary for shared queue-store state.
        class PersistenceMutex
          LOCK_TTL_SECONDS = 5
          LOCK_POLL_INTERVAL = 0.01
          RELEASE_SCRIPT = <<~LUA
            if redis.call("get", KEYS[1]) == ARGV[1] then
              return redis.call("del", KEYS[1])
            end
            return 0
          LUA

          def initialize(redis:, owner:, state_key:, lock_key:)
            @redis = redis
            @owner = owner
            @state_key = state_key
            @lock_key = lock_key
            @local_mutex = Thread::Mutex.new
          end

          def synchronize
            local_mutex.synchronize do
              with_distributed_lock do
                owner.send(:load_persisted_state)
                result = yield
                owner.send(:persist_state)
                result
              end
            end
          end

          private

          attr_reader :lock_key, :local_mutex, :owner, :redis, :state_key

          def with_distributed_lock
            token = SecureRandom.uuid
            sleep(LOCK_POLL_INTERVAL) until redis.set(lock_key, token, nx: true, ex: LOCK_TTL_SECONDS)

            yield
          ensure
            release_lock(token) if token
          end

          def release_lock(token)
            redis.eval(RELEASE_SCRIPT, keys: [lock_key], argv: [token])
          rescue StandardError
            return if redis.get(lock_key) != token

            redis.del(lock_key)
          end
        end
      end
    end
  end
end
