# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::InMemory do
  subject(:store) { described_class.new(token_generator: token_generator) }

  let(:token_sequence) { %w[lease-1 lease-2 lease-3 lease-4].each }
  let(:token_generator) { -> { token_sequence.next } }
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }

  describe '#initialize' do
    it 'supports default initialization' do
      store = described_class.new

      expect(store).to be_a(described_class)
    end

    it 'uses the default token generator when reserving jobs' do
      store = described_class.new
      job = Karya::Job.new(
        id: 'job-1',
        queue: 'billing',
        handler: 'billing_sync',
        state: :submission,
        created_at: created_at
      )

      store.enqueue(job:, now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      expect(reservation.token).to match(/\A[\w-]+:1\z/)
    end

    it 'rejects negative expired tombstone limits' do
      expect do
        described_class.new(expired_tombstone_limit: -1)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /finite non-negative Integer/)
    end

    it 'rejects nil expired tombstone limits' do
      expect do
        described_class.new(expired_tombstone_limit: nil)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /finite non-negative Integer/)
    end

    it 'rejects non-integer expired tombstone limits' do
      expect do
        described_class.new(expired_tombstone_limit: Float::INFINITY)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /finite non-negative Integer/)
    end

    it 'rejects invalid max batch size values' do
      expect do
        described_class.new(max_batch_size: 0)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /max_batch_size must be a positive Integer/)
    end

    it 'rejects unknown keyword options' do
      expect do
        described_class.new(unknown_option: true)
      end.to raise_error(ArgumentError, 'unknown keywords: unknown_option')
    end

    it 'rejects invalid policy_set values' do
      expect do
        described_class.new(policy_set: Object.new)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /policy_set must be a Karya::Backpressure::PolicySet/)
    end

    it 'rejects invalid circuit_breaker_policy_set values' do
      expect do
        described_class.new(circuit_breaker_policy_set: Object.new)
      end.to raise_error(
        Karya::InvalidQueueStoreOperationError,
        /circuit_breaker_policy_set must be a Karya::CircuitBreaker::PolicySet/
      )
    end

    it 'rejects invalid fairness_policy values' do
      expect do
        described_class.new(fairness_policy: Object.new)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /fairness_policy must be a Karya::Fairness::Policy/)
    end

    it 'rejects non-string generated reservation tokens' do
      token_store = described_class.new(token_generator: -> { 123 })
      token_store.enqueue(
        job: Karya::Job.new(
          id: 'job-1',
          queue: 'billing',
          handler: 'billing_sync',
          state: :submission,
          created_at:
        ),
        now: created_at + 1
      )

      expect do
        token_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /token must be a String/)
    end
  end

  describe 'internal state helpers' do
    it 'keeps the internal namespace private' do
      expect do
        described_class::Internal
      end.to raise_error(NameError, /private constant/)
    end

    it 'removes old direct support module constants' do
      expect do
        described_class::OperationsSupport
      end.to raise_error(NameError, /uninitialized constant/)
    end
  end
end
