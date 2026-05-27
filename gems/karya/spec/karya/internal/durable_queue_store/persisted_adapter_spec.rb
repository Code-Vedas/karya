# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::PersistedAdapter do
  let(:engine) { instance_double(Karya::Internal::DurableQueueStore::Engine) }
  let(:store_class) do
    Class.new do
      include Karya::Internal::DurableQueueStore::PersistedAdapter

      attr_accessor :persistence_mutex
    end
  end
  let(:store) { store_class.new }

  before do
    allow(store).to receive(:persisted_engine).and_return(engine)
  end

  it 'dispatches queue lifecycle methods through the durable engine' do
    allow(engine).to receive(:execute).and_return(:ok)

    expect(store.enqueue(job: :job, now: Time.utc(2026, 5, 23, 12, 0, 0))).to eq(:ok)
    expect(store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: Time.utc(2026, 5, 23, 12, 0, 1))).to eq(:ok)
    expect(store.complete_execution(reservation_token: 'token-1', now: Time.utc(2026, 5, 23, 12, 0, 2))).to eq(:ok)

    expect(engine).to have_received(:execute).with(
      operation_name: :enqueue,
      request: { job: :job, now: Time.utc(2026, 5, 23, 12, 0, 0) }
    )
    expect(engine).to have_received(:execute).with(
      operation_name: :reserve,
      request: { queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: Time.utc(2026, 5, 23, 12, 0, 1) }
    )
    expect(engine).to have_received(:execute).with(
      operation_name: :complete_execution,
      request: { reservation_token: 'token-1', now: Time.utc(2026, 5, 23, 12, 0, 2) }
    )
  end

  it 'dispatches uniqueness reads through the durable engine' do
    allow(engine).to receive(:execute).and_return(:snapshot)

    expect(store.uniqueness_decision(job: :job, now: Time.utc(2026, 5, 23, 12, 0, 3))).to eq(:snapshot)
    expect(store.uniqueness_snapshot(now: Time.utc(2026, 5, 23, 12, 0, 4))).to eq(:snapshot)

    expect(engine).to have_received(:execute).with(
      operation_name: :uniqueness_decision,
      request: { job: :job, now: Time.utc(2026, 5, 23, 12, 0, 3) }
    )
    expect(engine).to have_received(:execute).with(
      operation_name: :uniqueness_snapshot,
      request: { now: Time.utc(2026, 5, 23, 12, 0, 4) }
    )
  end

  it 'rejects invalid circuit breaker policy sets during persisted store configuration' do
    initializer_options_class = Class.new do
      attr_reader :expired_tombstone_limit,
                  :completed_batch_retention_limit,
                  :max_batch_size,
                  :token_generator,
                  :policy_set,
                  :circuit_breaker_policy_set,
                  :fairness_policy

      def initialize(_options)
        @expired_tombstone_limit = 1
        @completed_batch_retention_limit = 1
        @max_batch_size = 1
        @token_generator = -> { 'token' }
        @policy_set = Karya::Backpressure::PolicySet.new
        @circuit_breaker_policy_set = Object.new
        @fairness_policy = Karya::Fairness::Policy.new
      end
    end
    allow(store).to receive(:validation_support).and_return(
      Class.new do
        def validate_initializer_limits(**); end
      end.new
    )

    expect do
      store.configure_persisted_queue_store(initializer_options_class:)
    end.to raise_error(
      Karya::InvalidQueueStoreOperationError,
      'circuit_breaker_policy_set must be a Karya::CircuitBreaker::PolicySet'
    )
  end

  it 'rejects invalid backpressure policy sets during persisted store configuration' do
    initializer_options_class = Class.new do
      attr_reader :expired_tombstone_limit,
                  :completed_batch_retention_limit,
                  :max_batch_size,
                  :token_generator,
                  :policy_set,
                  :circuit_breaker_policy_set,
                  :fairness_policy

      def initialize(_options)
        @expired_tombstone_limit = 1
        @completed_batch_retention_limit = 1
        @max_batch_size = 1
        @token_generator = -> { 'token' }
        @policy_set = Object.new
        @circuit_breaker_policy_set = Karya::CircuitBreaker::PolicySet.new
        @fairness_policy = Karya::Fairness::Policy.new
      end
    end
    allow(store).to receive(:validation_support).and_return(
      Class.new do
        def validate_initializer_limits(**); end
      end.new
    )

    expect do
      store.configure_persisted_queue_store(initializer_options_class:)
    end.to raise_error(
      Karya::InvalidQueueStoreOperationError,
      'policy_set must be a Karya::Backpressure::PolicySet'
    )
  end

  it 'rejects invalid fairness policies during persisted store configuration' do
    initializer_options_class = Class.new do
      attr_reader :expired_tombstone_limit,
                  :completed_batch_retention_limit,
                  :max_batch_size,
                  :token_generator,
                  :policy_set,
                  :circuit_breaker_policy_set,
                  :fairness_policy

      def initialize(_options)
        @expired_tombstone_limit = 1
        @completed_batch_retention_limit = 1
        @max_batch_size = 1
        @token_generator = -> { 'token' }
        @policy_set = Karya::Backpressure::PolicySet.new
        @circuit_breaker_policy_set = Karya::CircuitBreaker::PolicySet.new
        @fairness_policy = Object.new
      end
    end
    allow(store).to receive(:validation_support).and_return(
      Class.new do
        def validate_initializer_limits(**); end
      end.new
    )

    expect do
      store.configure_persisted_queue_store(initializer_options_class:)
    end.to raise_error(
      Karya::InvalidQueueStoreOperationError,
      'fairness_policy must be a Karya::Fairness::Policy'
    )
  end

  it 'rejects positional arguments for persisted operations' do
    expect do
      store.send(:execute_persisted_operation, :enqueue, [:bad], {})
    end.to raise_error(ArgumentError, /positional arguments are not supported/)
  end
end
