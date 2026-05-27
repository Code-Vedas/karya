# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::Postgres do
  it 'rejects invalid values, token_generator overrides, and swallows type map setup failures' do
    store = described_class.allocate
    stub_const('PG', Module.new) unless defined?(PG)
    stub_const('PG::BasicTypeMapForResults', Class.new) unless defined?(PG::BasicTypeMapForResults)

    expect do
      store.send(:normalize_url, '')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /non-empty String/)
    expect do
      store.send(:normalize_namespace, '   ')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /non-empty String/)
    expect do
      described_class.new(url: 'postgres://postgres@127.0.0.1:5432/karya', token_generator: -> { 'x' })
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /managed internally/)

    connection = Object.new
    connection.define_singleton_method(:type_map_for_results=) { |_value| raise TypeError, 'no type maps' }
    store.instance_variable_set(:@connection, connection)
    allow(PG::BasicTypeMapForResults).to receive(:new).with(connection).and_return(Object.new)

    expect(store.send(:configure_connection_type_maps)).to be_nil

    no_method_connection = Object.new
    no_method_connection.define_singleton_method(:type_map_for_results=) { |_value| raise NoMethodError, 'no map=' }
    store.instance_variable_set(:@connection, no_method_connection)
    allow(PG::BasicTypeMapForResults).to receive(:new).with(no_method_connection).and_return(Object.new)
    expect(store.send(:configure_connection_type_maps)).to be_nil

    hide_const('PG::BasicTypeMapForResults') if defined?(PG::BasicTypeMapForResults)
    expect(store.send(:configure_connection_type_maps)).to be_nil
    expect(described_class::PresentString.new(123).normalize).to be_nil
  end

  it 'closes the postgres connection when initialization fails after connect' do
    stub_const('PG', Module.new) unless defined?(PG)
    connection_class = Class.new do
      def close; end
    end
    stub_const('PG::Connection', connection_class) unless defined?(PG::Connection)
    connection = instance_double(connection_class, close: nil)
    instance = described_class.allocate
    allow(Karya::QueueStore::Postgres::Internal::DependencyLoader).to receive(:require_pg!)
    allow(PG).to receive(:connect).and_return(connection)
    allow(instance).to receive(:configure_connection_type_maps)
    allow(instance).to receive(:configure_persisted_queue_store).and_raise(StandardError, 'boom')

    expect do
      instance.send(:initialize, url: 'postgres://postgres@127.0.0.1:5432/karya')
    end.to raise_error(StandardError, 'boom')
    expect(connection).to have_received(:close)
  end

  it 'initializes the persisted adapter and schema on a live connection' do
    stub_const('PG', Module.new) unless defined?(PG)
    connection_class = Class.new do
      attr_accessor :type_map_for_results

      def close; end
    end
    stub_const('PG::Connection', connection_class) unless defined?(PG::Connection)
    stub_const('PG::BasicTypeMapForResults', Class.new) unless defined?(PG::BasicTypeMapForResults)

    connection = instance_double(connection_class, close: nil)
    persistence_mutex = instance_double(Karya::QueueStore::Postgres::Internal::PersistenceMutex, ensure_schema: nil)
    store = described_class.allocate

    allow(Karya::QueueStore::Postgres::Internal::DependencyLoader).to receive(:require_pg!)
    allow(store).to receive(:configure_persisted_queue_store) do |**options|
      expect(options.fetch(:token_generator).call).to be_a(String)
    end
    allow(PG).to receive(:connect).with('postgres://postgres@127.0.0.1:5432/karya').and_return(connection)
    allow(PG::BasicTypeMapForResults).to receive(:new).with(connection).and_return(:type_map)
    allow(connection).to receive(:type_map_for_results=).with(:type_map)
    allow(Karya::QueueStore::Postgres::Internal::PersistenceMutex).to receive(:new)
      .with(connection:, owner: store)
      .and_return(persistence_mutex)

    store.send(:initialize, url: 'postgres://postgres@127.0.0.1:5432/karya')

    expect(store.connection).to equal(connection)
    expect(store.mutex).to equal(persistence_mutex)
    expect(store.persistence_mutex).to equal(persistence_mutex)
    expect(persistence_mutex).to have_received(:ensure_schema)
  end
end
