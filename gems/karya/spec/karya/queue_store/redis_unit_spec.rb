# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::Redis do
  it 'initializes the durable state store and persistence mutex with normalized configuration' do
    redis_client = instance_double(Redis)
    durable_state_store = instance_double(Karya::QueueStore::Redis::Internal::DurableStateStore)
    persistence_mutex = instance_double(Karya::QueueStore::Redis::Internal::PersistenceMutex)
    store = described_class.allocate

    allow(store).to receive(:configure_persisted_queue_store) do |**options|
      expect(options.fetch(:token_generator).call).to be_a(String)
    end
    allow(Redis).to receive(:new).with(url: 'redis://127.0.0.1:6379/15').and_return(redis_client)
    allow(Karya::QueueStore::Redis::Internal::DurableStateStore).to receive(:new)
      .with(redis: redis_client, namespace: 'spec')
      .and_return(durable_state_store)
    allow(Karya::QueueStore::Redis::Internal::PersistenceMutex).to receive(:new)
      .with(
        redis: redis_client,
        owner: store,
        durable_state_store: durable_state_store,
        lock_key: 'spec:queue_store:lock',
        version_key: 'spec:queue_store:version'
      )
      .and_return(persistence_mutex)

    store.send(:initialize, url: 'redis://127.0.0.1:6379/15', namespace: 'spec')

    expect(store.url).to eq('redis://127.0.0.1:6379/15')
    expect(store.namespace).to eq('spec')
    expect(store.mutex).to equal(persistence_mutex)
    expect(store.persistence_mutex).to equal(persistence_mutex)
  end

  it 'rejects invalid urls, namespaces, and token_generator overrides' do
    store = described_class.allocate

    expect do
      store.send(:normalize_url, '')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /non-empty String/)
    expect do
      store.send(:normalize_namespace, nil)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /non-empty String/)
    expect do
      described_class.new(url: 'redis://127.0.0.1:6379/15', token_generator: -> { 'x' })
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /managed internally/)
  end
end
