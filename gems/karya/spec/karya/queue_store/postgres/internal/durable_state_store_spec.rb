# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::Postgres::Internal::DurableStateStore do
  let(:connection) { instance_double(Object) }
  let(:store) { described_class.new(connection:) }

  it 'normalizes time and integer string columns' do
    expect(store.send(:normalize_value, :updated_at, '2026-05-23T12:00:00Z')).to eq(Time.utc(2026, 5, 23, 12, 0, 0))
    expect(store.send(:normalize_value, :attempt, '5')).to eq(5)
  end
end
