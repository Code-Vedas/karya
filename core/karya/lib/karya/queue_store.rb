# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  # Raised when enqueue intent conflicts with existing job identity.
  class DuplicateJobError < Error; end

  # Raised when a queue store operation receives invalid input or violates
  # queue store expectations.
  class InvalidQueueStoreOperationError < Error; end

  # Raised when an enqueue operation receives invalid input or violates
  # queue store expectations.
  class InvalidEnqueueError < InvalidQueueStoreOperationError; end

  # Raised when enqueue intent conflicts with an existing uniqueness key.
  class DuplicateUniquenessKeyError < InvalidEnqueueError; end

  # Raised when enqueue intent conflicts with an existing idempotency key.
  class DuplicateIdempotencyKeyError < InvalidEnqueueError; end

  # Raised when a reservation token is unknown to the queue store.
  class UnknownReservationError < Error; end

  # Raised when a reservation token exists but is no longer active.
  class ExpiredReservationError < Error; end

  # Raised when a generated reservation token collides with an active lease.
  class DuplicateReservationTokenError < Error; end

  # Namespace for queue store implementations.
  module QueueStore
    autoload :Base, 'karya/queue_store/base'
    autoload :BulkMutationReport, 'karya/queue_store/bulk_mutation_report'
    autoload :InMemory, 'karya/queue_store/in_memory'
    autoload :QueueControlResult, 'karya/queue_store/queue_control_result'
    autoload :RecoveryReport, 'karya/queue_store/recovery_report'
  end
end
