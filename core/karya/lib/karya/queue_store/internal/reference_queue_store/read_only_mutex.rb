# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    module Internal
      module ReferenceQueueStore
        module Internal
          # Thread mutex wrapper that exposes the same read-only lock API as Redis persistence mutexes.
          class ReadOnlyMutex
            def initialize
              @mutex = Thread::Mutex.new
            end

            def synchronize(&)
              mutex.synchronize(&)
            end

            def read_only_synchronize(&)
              mutex.synchronize(&)
            end

            private

            attr_reader :mutex
          end
        end
      end
    end
  end
end
