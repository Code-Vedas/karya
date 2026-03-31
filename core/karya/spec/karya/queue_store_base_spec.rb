# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore do
  subject(:store) { implementation.new }

  let(:implementation) do
    Class.new do
      include Karya::QueueStore::Base
    end
  end

  it 'requires enqueue to be implemented' do
    expect do
      store.enqueue(job: instance_double(Karya::Job), now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #enqueue/)
  end

  it 'requires reserve to be implemented' do
    expect do
      store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #reserve/)
  end

  it 'requires release to be implemented' do
    expect do
      store.release(reservation_token: 'lease-1', now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #release/)
  end

  it 'requires start_execution to be implemented' do
    expect do
      store.start_execution(reservation_token: 'lease-1', now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #start_execution/)
  end

  it 'requires complete_execution to be implemented' do
    expect do
      store.complete_execution(reservation_token: 'lease-1', now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #complete_execution/)
  end

  it 'requires fail_execution to be implemented' do
    expect do
      store.fail_execution(reservation_token: 'lease-1', now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #fail_execution/)
  end

  it 'requires expire_reservations to be implemented' do
    expect do
      store.expire_reservations(now: Time.utc(2026, 3, 27, 12, 0, 0))
    end.to raise_error(NotImplementedError, /implement #expire_reservations/)
  end
end
