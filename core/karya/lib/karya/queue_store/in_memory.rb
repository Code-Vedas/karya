# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require 'bigdecimal'

require_relative 'base'
require_relative 'internal'
require_relative '../circuit_breaker'
require_relative '../fairness'
require_relative '../internal/bulk_mutation'
require_relative '../internal/failure_classification'
require_relative '../internal/retry_policy_normalizer'
require_relative 'in_memory/internal'
require_relative '../internal/reference_queue_store'
require_relative '../job'
require_relative '../primitives/callable'
require_relative '../primitives/identifier'
require_relative '../primitives/queue_list'
require_relative '../reservation'
require_relative '../retry_policy'
require_relative '../backpressure'
require_relative '../workflow'

module Karya
  module QueueStore
    # Single-process reference implementation for queue submission and reservation behavior.
    # InMemory is intentionally ephemeral and suitable for development, tests,
    # examples, and as the executable reference for `QueueStore::Base` semantics.
    # It is not a durable backend: jobs, queue indexes, reservations, active
    # executions, retry state, and expired-token tombstones live only in
    # process memory and are lost on restart. Production deployments that need
    # durable enqueue acknowledgment or restart/takeover recovery must use a
    # shared persistent backend implementing the Base durability contract.
    class InMemory
      # Owner-local implementation helpers for the executable reference store.
      module Internal
        StoreState = Karya::QueueStore::Internal::StoreState
      end

      include Karya::Internal::ReferenceQueueStore

      DEFAULT_EXPIRED_TOMBSTONE_LIMIT = Karya::Internal::ReferenceQueueStore::DEFAULT_EXPIRED_TOMBSTONE_LIMIT
      DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT = Karya::Internal::ReferenceQueueStore::DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT
      DEFAULT_MAX_BATCH_SIZE = Karya::Internal::ReferenceQueueStore::DEFAULT_MAX_BATCH_SIZE
      RESERVE_QUEUES_ERROR_MESSAGE = Karya::Internal::ReferenceQueueStore::RESERVE_QUEUES_ERROR_MESSAGE

      def initialize(**)
        configure_reference_queue_store(
          initializer_options_class: Internal::InitializerOptions,
          store_state_class: Internal::StoreState,
          **
        )
      end

      private_constant :Internal
    end
  end
end
