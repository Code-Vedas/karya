# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::SQLite::Internal::QueryBuilder do
  it 'builds reserve candidate sql with and without handler filters' do
    sql, params = described_class.reserve_candidate_query(
      queue_entries_table: 'queue_entries',
      handler_names: %w[a b]
    )
    expect(sql).to include('handler IN (?, ?)')
    expect(params).to eq(%w[a b])

    sql, params = described_class.reserve_candidate_query(
      queue_entries_table: 'queue_entries',
      handler_names: nil
    )
    expect(sql).not_to include('handler IN')
    expect(params).to be_nil
  end

  it 'builds queue entry sql with and without queue filters' do
    sql, params = described_class.queue_entry_query(
      queue_entries_table: 'queue_entries',
      queue_entries_order: 'ORDER BY queue ASC',
      namespace: 'tenant-a',
      queues: %w[billing critical],
      state_name: 'queued'
    )
    expect(sql).to include('queue IN (?, ?)')
    expect(params).to eq(%w[tenant-a billing critical])

    sql, params = described_class.queue_entry_query(
      queue_entries_table: 'queue_entries',
      queue_entries_order: 'ORDER BY queue ASC',
      namespace: 'tenant-a',
      queues: nil,
      state_name: 'retry_pending'
    )
    expect(sql).not_to include('queue IN')
    expect(sql).to include("state = 'retry_pending'")
    expect(params).to eq(['tenant-a'])
  end
end
