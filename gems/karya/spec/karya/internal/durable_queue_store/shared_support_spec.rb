# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::SharedSupport do
  let(:host_class) do
    Class.new do
      include Karya::Internal::DurableQueueStore::SharedSupport

      public :validate_initializer_limits, :normalize_identifier, :normalize_time
    end
  end
  let(:host) { host_class.new }
  let(:now) { Time.utc(2026, 5, 23, 12, 0, 0) }

  it 'accepts valid initializer limits' do
    expect do
      host.validate_initializer_limits(
        expired_tombstone_limit: 0,
        completed_batch_retention_limit: 1,
        max_batch_size: 2
      )
    end.not_to raise_error
  end

  it 'rejects invalid initializer limits' do
    expect do
      host.validate_initializer_limits(
        expired_tombstone_limit: -1,
        completed_batch_retention_limit: 1,
        max_batch_size: 2
      )
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /expired_tombstone_limit/)

    expect do
      host.validate_initializer_limits(
        expired_tombstone_limit: 1,
        completed_batch_retention_limit: -1,
        max_batch_size: 2
      )
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /completed_batch_retention_limit/)

    expect do
      host.validate_initializer_limits(
        expired_tombstone_limit: 1,
        completed_batch_retention_limit: 1,
        max_batch_size: 0
      )
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /max_batch_size/)
  end

  it 'normalizes identifiers and rejects nil or non-string inputs' do
    expect(host.normalize_identifier(:queue, " billing \n", error_class: Karya::InvalidQueueStoreOperationError)).to eq('billing')

    expect do
      host.normalize_identifier(:queue, nil, error_class: Karya::InvalidQueueStoreOperationError)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'queue must be present')

    expect do
      host.normalize_identifier(:queue, 123, error_class: Karya::InvalidQueueStoreOperationError)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'queue must be a String')
  end

  it 'accepts times and rejects non-times' do
    expect(host.normalize_time(:now, now, error_class: Karya::InvalidQueueStoreOperationError)).to eq(now)

    expect do
      host.normalize_time(:now, '2026-05-23', error_class: Karya::InvalidQueueStoreOperationError)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'now must be a Time')
  end
end
