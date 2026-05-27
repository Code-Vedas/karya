# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::MySQL do
  it 'rejects invalid urls, long namespaces, and token_generator overrides' do
    expect do
      described_class::ConnectionOptions.build(
        url: 'postgres://root@127.0.0.1:3306/karya',
        present_string_class: described_class::PresentString
      )
    end.to raise_error(Karya::InvalidQueueStoreOperationError, %r{mysql://})

    expect do
      described_class::ConnectionOptions.build(
        url: 'mysql2://root@127.0.0.1:3306',
        present_string_class: described_class::PresentString
      )
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /database name/)

    socket_options = described_class::ConnectionOptions.build(
      url: 'mysql2://root@localhost/karya?socket=%2Ftmp%2Fmysql.sock&encoding=latin1',
      present_string_class: described_class::PresentString
    )
    expect(socket_options).to include(socket: '/tmp/mysql.sock', encoding: 'latin1')
    expect(socket_options).not_to have_key(:host)

    store = described_class.allocate
    expect do
      store.send(:normalize_url, '')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /non-empty String/)
    expect(described_class::PresentString.new(123).normalize).to be_nil
    expect do
      described_class::ConnectionOptions.build(
        url: 'mysql2://%zz',
        present_string_class: described_class::PresentString
      )
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid MySQL url/)
    expect do
      store.send(:normalize_namespace, nil)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /non-empty String/)
    expect do
      store.send(:normalize_namespace, 'x' * 256)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /at most 255/)
    expect do
      described_class.new(url: 'mysql2://root@127.0.0.1:3306/karya', token_generator: -> { 'x' })
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /managed internally/)
  end

  it 'closes the mysql connection when initialization fails after connect' do
    stub_const('Mysql2', Module.new) unless defined?(Mysql2)
    client_class = Class.new
    stub_const('Mysql2::Client', client_class)
    connection = instance_double(client_class, query: nil, close: nil)
    instance = described_class.allocate
    allow(Karya::QueueStore::MySQL::Internal::DependencyLoader).to receive(:require_mysql2!)
    allow(Mysql2::Client).to receive(:new).and_return(connection)
    allow(instance).to receive(:configure_persisted_queue_store).and_raise(StandardError, 'boom')

    expect do
      instance.send(:initialize, url: 'mysql2://root@127.0.0.1:3306/karya')
    end.to raise_error(StandardError, 'boom')
    expect(connection).to have_received(:close)
  end

  it 'initializes the persisted adapter and schema on a live connection' do
    stub_const('Mysql2', Module.new) unless defined?(Mysql2)
    client_class = Class.new
    stub_const('Mysql2::Client', client_class)
    connection = instance_double(client_class, query: nil, close: nil)
    persistence_mutex = instance_double(Karya::QueueStore::MySQL::Internal::PersistenceMutex, ensure_schema: nil)
    store = described_class.allocate

    allow(Karya::QueueStore::MySQL::Internal::DependencyLoader).to receive(:require_mysql2!)
    allow(store).to receive(:configure_persisted_queue_store) do |**options|
      expect(options.fetch(:token_generator).call).to be_a(String)
    end
    allow(Mysql2::Client).to receive(:new)
      .with(username: 'root', host: '127.0.0.1', port: 3306, database: 'karya', encoding: 'utf8mb4')
      .and_return(connection)
    allow(Karya::QueueStore::MySQL::Internal::PersistenceMutex).to receive(:new)
      .with(connection:, owner: store)
      .and_return(persistence_mutex)

    store.send(:initialize, url: 'mysql2://root@127.0.0.1:3306/karya')

    expect(connection).to have_received(:query).with("SET time_zone = '+00:00'")
    expect(store.connection).to equal(connection)
    expect(store.mutex).to equal(persistence_mutex)
    expect(store.persistence_mutex).to equal(persistence_mutex)
    expect(persistence_mutex).to have_received(:ensure_schema)
  end
end
