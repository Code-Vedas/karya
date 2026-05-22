# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::Engine do
  let(:metadata) { { reservation_token_sequence: 0 } }
  let(:rows) { { jobs: [], queue_entries: [], reservations: [], policy_state: [] } }
  let(:state_store_class) do
    Class.new do
      def fetch_metadata(namespace:); end
      def fetch_rows_for_operation(operation_name:, namespace:, request:); end
      def lock_rows_for_operation(operation_name:, namespace:, request:, metadata:, rows:); end
      def apply_mutation_plan(plan:, namespace:); end
    end
  end
  let(:mutex_class) do
    Class.new do
      def run_read_only(operation_name:); end
      def run_reserve(operation_name:); end
      def run_mutation(operation_name:); end
    end
  end
  let(:state_store) { instance_double(state_store_class) }
  let(:mutex) { instance_double(mutex_class) }
  let(:store_class) do
    Class.new do
      attr_accessor :namespace, :persistence_mutex
      attr_reader :durable_state_store

      def initialize(durable_state_store:)
        @namespace = 'karya'
        @durable_state_store = durable_state_store
      end

      private :durable_state_store
    end
  end
  let(:store) { store_class.new(durable_state_store: state_store) }
  let(:engine) { described_class.new(store:) }

  before do
    store.persistence_mutex = mutex
    allow(state_store).to receive_messages(
      fetch_metadata: metadata,
      fetch_rows_for_operation: rows,
      lock_rows_for_operation: nil,
      apply_mutation_plan: nil
    )
  end

  it 'uses the read-only boundary for uniqueness reads' do
    allow(mutex).to receive(:run_read_only).and_yield

    snapshot = engine.execute(operation_name: :uniqueness_snapshot, request: { now: Time.utc(2026, 5, 23, 12, 0, 0) })

    expect(mutex).to have_received(:run_read_only).with(operation_name: :uniqueness_snapshot)
    expect(snapshot).to include(:captured_at, :idempotency_keys, :uniqueness_keys)
    expect(state_store).not_to have_received(:apply_mutation_plan)
  end

  it 'uses the reserve boundary for reserve' do
    allow(mutex).to receive(:run_reserve).and_yield

    reservation = engine.execute(
      operation_name: :reserve,
      request: { queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: Time.utc(2026, 5, 23, 12, 0, 1) }
    )

    expect(mutex).to have_received(:run_reserve).with(operation_name: :reserve)
    expect(reservation).to be_nil
  end

  it 'uses the mutation boundary for enqueue' do
    allow(mutex).to receive(:run_mutation).and_yield

    job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'ProcessInvoice',
      arguments: {},
      state: :submission,
      created_at: Time.utc(2026, 5, 23, 12, 0, 1)
    )
    queued_job = engine.execute(operation_name: :enqueue, request: { job:, now: Time.utc(2026, 5, 23, 12, 0, 2) })

    expect(mutex).to have_received(:run_mutation).with(operation_name: :enqueue)
    expect(state_store).to have_received(:apply_mutation_plan).with(
      plan: an_instance_of(Karya::Internal::DurableQueueStore::MutationPlan),
      namespace: 'karya'
    )
    expect(queued_job.state).to eq(:queued)
  end

  it 'returns raw operation values without trying to persist them' do
    allow(engine).to receive_messages(
      build_operation: instance_double(Karya::Internal::DurableQueueStore::Operation, call: :raw),
      operation_context: Karya::Internal::DurableQueueStore::OperationContext.new(
        namespace: 'karya',
        request: {},
        metadata:,
        rows:
      )
    )

    expect(engine.execute(operation_name: :enqueue, request: {})).to eq(:raw)
    expect(state_store).not_to have_received(:apply_mutation_plan)
  end

  it 'skips persistence when the operation result has an empty mutation plan' do
    operation = instance_double(Karya::Internal::DurableQueueStore::Operation)
    result = Karya::Internal::DurableQueueStore::OperationResult.new(
      value: :ok,
      mutation_plan: Karya::Internal::DurableQueueStore::MutationPlan.new,
      persist: true
    )
    allow(operation).to receive(:call).and_return(result)
    allow(engine).to receive_messages(
      build_operation: operation,
      operation_context: Karya::Internal::DurableQueueStore::OperationContext.new(
        namespace: 'karya',
        request: {},
        metadata:,
        rows:
      )
    )

    expect(engine.execute(operation_name: :enqueue, request: {})).to eq(:ok)
    expect(state_store).not_to have_received(:apply_mutation_plan)
  end
end
