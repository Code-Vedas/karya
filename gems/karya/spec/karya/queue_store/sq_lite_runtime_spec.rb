# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::SQLite do
  describe described_class::ConnectionPath do
    it 'builds paths for sqlite file urls and host-qualified sqlite urls' do
      present_string_class = Karya::QueueStore::SQLite::PresentString

      expect(described_class.build(url: 'sqlite:///tmp/app.sqlite3', present_string_class:)).to eq('/tmp/app.sqlite3')
      expect(
        described_class.build(
          url: 'sqlite://server/share/app.sqlite3',
          present_string_class:
        )
      ).to eq('server/share/app.sqlite3')
    end

    it 'rejects invalid schemes, missing paths, and malformed urls' do
      present_string_class = Karya::QueueStore::SQLite::PresentString

      expect do
        described_class.build(url: 'postgres:///tmp/app.sqlite3', present_string_class:)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, %r{sqlite://})

      expect do
        described_class.build(url: 'sqlite:///:memory:', present_string_class:)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /durable SQLite file path/)

      expect do
        described_class.build(url: 'sqlite:///%zz', present_string_class:)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid SQLite url/)
    end
  end

  describe described_class::ConnectionBuilder do
    it 'ignores missing busy_timeout support' do
      stub_const('SQLite3', Module.new) unless defined?(SQLite3)
      database_class = Class.new
      stub_const('SQLite3::Database', database_class)
      database = instance_double(database_class)
      allow(database).to receive(:results_as_hash=).with(true)
      allow(database).to receive(:busy_timeout=).with(5000).and_raise(NoMethodError, 'busy_timeout=')
      allow(SQLite3::Database).to receive(:new).with('/tmp/test.sqlite3').and_return(database)

      expect(described_class.build('/tmp/test.sqlite3')).to equal(database)
    end
  end

  describe '#initialize and private runtime helpers' do
    let(:store) { described_class.allocate }

    it 'rejects blank url and namespace values' do
      expect do
        store.send(:normalize_url, '   ')
      end.to raise_error(Karya::InvalidQueueStoreOperationError, 'url must be a non-empty String')

      expect do
        store.send(:normalize_namespace, nil)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, 'namespace must be a non-empty String')

      store.instance_variable_set(:@connection_pid, Process.pid)
      store.instance_variable_set(:@connection, Object.new)
      store.instance_variable_set(:@persistence_mutex, :mutex)
      expect(store.mutex).to eq(:mutex)
    end

    it 'rejects token_generator overrides before touching dependencies' do
      expect do
        described_class.new(url: 'sqlite:///tmp/app.sqlite3', token_generator: -> { 'x' })
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /managed internally/)
    end

    it 'closes the connection when initialization fails after opening it' do
      database_class = Class.new do
        def close; end
      end
      connection = instance_double(database_class, close: nil)
      instance = described_class.allocate
      allow(Karya::QueueStore::SQLite::Internal::DependencyLoader).to receive(:require_sqlite3!)
      allow(instance).to receive(:build_connection).and_return(connection)
      allow(instance).to receive(:configure_persisted_queue_store).and_raise(StandardError, 'boom')

      expect do
        instance.send(:initialize, url: 'sqlite:///tmp/app.sqlite3')
      end.to raise_error(StandardError, 'boom')
      expect(connection).to have_received(:close)
    end

    it 'rebuilds connection state across forks and clears state on reconnect failure' do
      database_class = Class.new do
        def close; end
      end
      old_connection = instance_double(database_class, close: nil)
      new_connection = instance_double(database_class)
      new_mutex = Object.new

      store.instance_variable_set(:@connection, old_connection)
      store.instance_variable_set(:@connection_pid, Process.pid - 1)
      store.instance_variable_set(:@persistence_mutex, :old_mutex)
      store.instance_variable_set(:@mutex, :old_mutex)

      allow(store).to receive(:build_connection).and_return(new_connection)
      allow(store).to receive(:build_persistence_mutex).with(new_connection).and_return(new_mutex)
      expect(store.send(:build_persistence_mutex, new_connection)).to equal(new_mutex)

      store.send(:reconnect_if_needed)

      expect(old_connection).to have_received(:close)
      expect(store.instance_variable_get(:@connection)).to equal(new_connection)
      expect(store.instance_variable_get(:@persistence_mutex)).to equal(new_mutex)
      expect(store.instance_variable_get(:@mutex)).to equal(new_mutex)

      failing_connection = instance_double(database_class, close: nil)
      store.instance_variable_set(:@connection, failing_connection)
      store.instance_variable_set(:@connection_pid, Process.pid - 1)
      store.instance_variable_set(:@persistence_mutex, :stale)
      store.instance_variable_set(:@mutex, :stale)
      allow(store).to receive(:build_connection).and_raise(StandardError, 'reconnect failed')

      expect do
        store.send(:reconnect_if_needed)
      end.to raise_error(StandardError, 'reconnect failed')
      expect(store.instance_variable_get(:@connection)).to be_nil
      expect(store.instance_variable_get(:@persistence_mutex)).to be_nil
      expect(store.instance_variable_get(:@mutex)).to be_nil

      store.instance_variable_set(:@connection, nil)
      store.instance_variable_set(:@connection_pid, Process.pid - 1)
      allow(store).to receive(:build_connection).and_return(new_connection)
      allow(store).to receive(:build_persistence_mutex).with(new_connection).and_return(new_mutex)

      expect(store.send(:reconnect_if_needed)).to be_nil
      expect(store.instance_variable_get(:@connection)).to equal(new_connection)
    end

    it 'falls back when close wrapping cannot attach and clears/tears down connections explicitly' do
      database = Object.new
      allow(database).to receive(:method).with(:close).and_raise(NameError, 'no close')

      expect(store.send(:wrap_connection_close, database)).to equal(database)

      other_database = Object.new
      store.instance_variable_set(:@connection, database)
      store.instance_variable_set(:@connection_pid, Process.pid)

      expect(store.send(:clear_connection_reference, other_database)).to be_nil
      expect(store.instance_variable_get(:@connection)).to equal(database)

      database_class = Class.new do
        def close; end
      end
      closable = instance_double(database_class, close: nil)
      store.instance_variable_set(:@connection, closable)
      store.instance_variable_set(:@connection_pid, Process.pid)
      store.instance_variable_set(:@persistence_mutex, :mutex)
      store.instance_variable_set(:@mutex, :mutex)

      expect(store.send(:disconnect_for_fork)).to be_nil
      expect(closable).to have_received(:close)
      expect(store.instance_variable_get(:@connection)).to be_nil
      expect(store.instance_variable_get(:@connection_pid)).to be_nil
      expect(store.instance_variable_get(:@persistence_mutex)).to be_nil
      expect(store.instance_variable_get(:@mutex)).to be_nil

      expect(store.send(:build_persistence_mutex, closable)).to be_a(Karya::QueueStore::SQLite::Internal::PersistenceMutex)

      expect(store.send(:disconnect_for_fork)).to be_nil
    end
  end
end
