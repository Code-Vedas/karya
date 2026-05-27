# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::Redis::Internal::PersistenceMutex do
  it 'yields all operation boundaries' do
    mutex = described_class.new(
      redis: Object.new,
      owner: Object.new,
      durable_state_store: Object.new,
      lock_key: 'lock',
      version_key: 'version'
    )

    expect(mutex.run_mutation(operation_name: :enqueue) { :write }).to eq(:write)
    expect(mutex.run_reserve(operation_name: :reserve) { :reserve }).to eq(:reserve)
    expect(mutex.run_read_only(operation_name: :uniqueness_snapshot) { :read }).to eq(:read)
  end
end
