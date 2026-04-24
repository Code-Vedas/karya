# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::BackpressureSupport' do
  let(:described_class) do
    Karya::QueueStore::InMemory.const_get(:Internal, false).const_get(:BackpressureSupport, false)
  end
  let(:store) { Karya::QueueStore::InMemory.new }
  let(:state) { store.instance_variable_get(:@state) }

  def stored_job
    Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      state: :queued,
      created_at: Time.utc(2026, 3, 27, 12, 0, 0),
      updated_at: Time.utc(2026, 3, 27, 12, 0, 1)
    )
  end

  it 'requires a block for each_scope_key' do
    expect do
      described_class.each_scope_key(stored_job, nil)
    end.to raise_error(ArgumentError, 'each_scope_key requires a block')
  end

  it 'removes orphaned rate-limit admission keys during stale-pruning maintenance' do
    state.rate_limit_admissions_by_key['orphan'] = [Time.utc(2026, 3, 27, 12, 0, 0)]

    store.send(:prune_stale_rate_limit_admissions, Time.utc(2026, 3, 27, 12, 0, 20))

    expect(state.rate_limit_admissions_by_key).to eq({})
  end
end
