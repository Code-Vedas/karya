# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class Redis
      module Internal
        # Stable mutex proxy that keeps replay bypass thread-local instead of swapping shared owner state.
        class ReferenceQueueStoreMutex
          def initialize(owner:, persistence_mutex:)
            @owner = owner
            @persistence_mutex = persistence_mutex
            @read_only_mutex = Karya::QueueStore::Internal::ReferenceQueueStore::Internal::ReadOnlyMutex.new
          end

          def synchronize(persist_if: nil, &)
            current_mutex.synchronize(persist_if:, &)
          end

          def synchronize_with_event(event_builder:, persist_if: nil, &)
            return read_only_mutex.synchronize(&) if owner.send(:bypass_reference_queue_persistence?)

            persistence_mutex.synchronize_with_event(event_builder:, persist_if:, &)
          end

          def read_only_synchronize(&)
            current_mutex.read_only_synchronize(&)
          end

          def compact_snapshot(payload:)
            persistence_mutex.compact_snapshot(payload:)
          end

          private

          attr_reader :owner, :persistence_mutex, :read_only_mutex

          def current_mutex
            owner.send(:bypass_reference_queue_persistence?) ? read_only_mutex : persistence_mutex
          end
        end
      end
    end
  end
end
