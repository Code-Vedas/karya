# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::MySQL::Internal::PersistenceMutex do
  let(:connection_class) do
    Class.new do
      def query(_statement); end
    end
  end
  let(:connection) { instance_double(connection_class) }
  let(:state_store) { instance_double(Karya::QueueStore::MySQL::Internal::DurableStateStore) }

  before do
    allow(Karya::QueueStore::MySQL::Internal::DurableStateStore).to receive(:new).with(connection:).and_return(state_store)
  end

  it 'ignores duplicate index errors while ensuring schema' do
    stub_const('Mysql2', Module.new) unless defined?(Mysql2)
    stub_const('Mysql2::Error', Class.new(StandardError)) unless defined?(Mysql2::Error)
    duplicate_error = Mysql2::Error.new('Duplicate key name').tap do |error|
      allow(error).to receive(:error_number).and_return(1061)
    end
    statements = Karya::Internal::DurableQueueStoreCatalog.mysql_create_statements
    allow(connection).to receive(:query).with(statements.first).and_raise(duplicate_error)
    statements.drop(1).each { |statement| allow(connection).to receive(:query).with(statement).and_return(nil) }

    mutex = described_class.new(connection:, owner: Object.new)

    expect(mutex.ensure_schema).to be_nil
  end

  it 're-raises non-duplicate mysql schema errors' do
    stub_const('Mysql2', Module.new) unless defined?(Mysql2)
    stub_const('Mysql2::Error', Class.new(StandardError)) unless defined?(Mysql2::Error)
    error = Mysql2::Error.new('boom')
    allow(error).to receive(:error_number).and_return(9999)
    allow(connection).to receive(:query).and_raise(error)

    mutex = described_class.new(connection:, owner: Object.new)

    expect do
      mutex.ensure_schema
    end.to raise_error(Mysql2::Error, /boom/)
  end

  it 'commits successful mutations and rolls back failing transactions' do
    mutex = described_class.new(connection:, owner: Object.new)
    allow(connection).to receive(:query).with('START TRANSACTION').and_return(nil)
    allow(connection).to receive(:query).with('COMMIT').and_return(nil)
    allow(connection).to receive(:query).with('ROLLBACK').and_return(nil)

    expect(mutex.run_mutation(operation_name: :enqueue) { :ok }).to eq(:ok)
    expect(connection).to have_received(:query).with('COMMIT')

    expect do
      mutex.run_reserve(operation_name: :reserve) { raise 'boom' }
    end.to raise_error(RuntimeError, 'boom')
    expect(connection).to have_received(:query).with('ROLLBACK')
    expect(mutex.run_read_only(operation_name: :uniqueness_snapshot) { :read }).to eq(:read)
  end
end
