# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::RequestSupport do
  let(:host_class) do
    Class.new do
      include Karya::Internal::DurableQueueStore::RequestSupport

      public :normalize_reserve_queues, :normalize_reserve_request
    end
  end
  let(:host) { host_class.new }
  let(:now) { Time.utc(2026, 5, 23, 12, 0, 0) }

  it 'normalizes a single queue reserve request' do
    request = host.normalize_reserve_request(
      worker_id: " worker-1 \n",
      lease_duration: 30,
      now:,
      queue: ' billing ',
      queues: nil,
      handler_names: %w[email_sync billing_sync]
    )

    expect(request.fetch(:queues)).to eq(['billing'])
    expect(request.fetch(:worker_id)).to eq('worker-1')
    expect(request.fetch(:lease_duration)).to eq(30)
    expect(request.fetch(:now)).to eq(now)
    expect(request.fetch(:handler_matcher)).to be_a(Karya::Internal::DurableQueueStore::HandlerMatcher)
    expect(request.fetch(:subscription_key)).to eq([['billing'], %w[billing_sync email_sync]])
  end

  it 'normalizes a queues list and accepts match-all handler selection' do
    expect(
      host.normalize_reserve_queues(queue: nil, queues: [" billing \n", 'email'])
    ).to eq(%w[billing email])

    request = host.normalize_reserve_request(
      worker_id: 'worker-1',
      lease_duration: Rational(3, 2),
      now:,
      queue: nil,
      queues: %w[billing email],
      handler_names: nil
    )

    expect(request.fetch(:subscription_key)).to eq([%w[billing email], nil])
  end

  it 'rejects missing or conflicting queue inputs' do
    expect do
      host.normalize_reserve_queues(queue: nil, queues: nil)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, Karya::Internal::DurableQueueStore::SharedSupport::RESERVE_QUEUES_ERROR_MESSAGE)

    expect do
      host.normalize_reserve_queues(queue: 'billing', queues: ['email'])
    end.to raise_error(Karya::InvalidQueueStoreOperationError, Karya::Internal::DurableQueueStore::SharedSupport::RESERVE_QUEUES_ERROR_MESSAGE)
  end

  it 'rejects invalid queue entry types' do
    expect do
      host.normalize_reserve_queues(queue: 123, queues: nil)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'queue must be a String')

    expect do
      host.normalize_reserve_queues(queue: nil, queues: ['billing', :email])
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'queues entries must be Strings')
  end
end
