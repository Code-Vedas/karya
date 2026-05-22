# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Backend::Postgres do
  it 'exposes the backend identifier' do
    expect(described_class.new(url: 'postgres://127.0.0.1/karya').identifier).to eq('postgres')
  end

  it 'builds the owned Postgres queue store with forwarded options' do
    queue_store = instance_double(Karya::QueueStore::Postgres)
    allow(Karya::QueueStore::Postgres).to receive(:new).and_return(queue_store)

    result = described_class.new(
      url: 'postgres://127.0.0.1/karya',
      namespace: 'payments',
      max_batch_size: 50
    ).build_queue_store

    expect(result).to be(queue_store)
    expect(Karya::QueueStore::Postgres).to have_received(:new).with(
      url: 'postgres://127.0.0.1/karya',
      namespace: 'payments',
      max_batch_size: 50
    )
  end

  it 'normalizes invalid keyword errors into backend configuration errors' do
    allow(Karya::QueueStore::Postgres).to receive(:new).and_raise(ArgumentError, 'unknown keywords: unsupported_option')

    expect do
      described_class.new(
        url: 'postgres://127.0.0.1/karya',
        unsupported_option: true
      ).build_queue_store
    end.to raise_error(
      Karya::InvalidBackendConfigurationError,
      /invalid Postgres backend queue-store configuration: unexpected option keys :unsupported_option: unknown keywords: unsupported_option/
    )
  end

  it 'normalizes queue-store validation errors into backend configuration errors' do
    error = Karya::InvalidQueueStoreOperationError.new('url must be a non-empty String')
    allow(Karya::QueueStore::Postgres).to receive(:new).and_raise(error)

    expect do
      described_class.new(url: ' ').build_queue_store
    end.to raise_error(
      Karya::InvalidBackendConfigurationError,
      /invalid Postgres backend queue-store configuration: url must be a non-empty String/
    ) { |raised_error| expect(raised_error.cause).to be(error) }
  end
end
