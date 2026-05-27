# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class Redis
      module Internal
        # Defines the execution boundary for durable Redis queue-store operations.
        class PersistenceMutex
          UNSUPPORTED_MESSAGE =
            'Redis durable operation boundary is not implemented yet'

          def initialize(redis:, owner:, durable_state_store:, lock_key:, version_key:)
            @redis = redis
            @owner = owner
            @durable_state_store = durable_state_store
            @lock_key = lock_key
            @version_key = version_key
          end

          def run_mutation(...)
            yield
          end

          def run_reserve(...)
            yield
          end

          def run_read_only(...)
            yield
          end

          private

          attr_reader :durable_state_store, :lock_key, :owner, :redis, :version_key
        end
      end
    end
  end
end
