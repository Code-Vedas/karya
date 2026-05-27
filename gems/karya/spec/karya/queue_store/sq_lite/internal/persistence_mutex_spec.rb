# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::SQLite::Internal::PersistenceMutex do
  let(:connection_class) do
    Class.new do
      def execute(_statement); end
      def execute_batch(_sql); end
    end
  end
  let(:connection) { instance_double(connection_class) }
  let(:state_store) { instance_double(Karya::QueueStore::SQLite::Internal::DurableStateStore) }

  before do
    allow(Karya::QueueStore::SQLite::Internal::DurableStateStore).to receive(:new).with(connection:).and_return(state_store)
  end

  it 'ensures schema and rolls back failing transactions' do
    allow(connection).to receive(:execute_batch).and_return(nil)
    allow(connection).to receive(:execute).with('BEGIN IMMEDIATE').and_return(nil)
    allow(connection).to receive(:execute).with('COMMIT').and_return(nil)
    allow(connection).to receive(:execute).with('ROLLBACK').and_return(nil)
    mutex = described_class.new(connection:, owner: Object.new)

    expect(mutex.ensure_schema).to be_nil
    expect(mutex.run_mutation(operation_name: :enqueue) { :ok }).to eq(:ok)

    expect do
      mutex.run_reserve(operation_name: :reserve) { raise 'boom' }
    end.to raise_error(RuntimeError, 'boom')
    expect(connection).to have_received(:execute).with('ROLLBACK')
    expect(mutex.run_read_only(operation_name: :uniqueness_snapshot) { :read }).to eq(:read)
  end
end
