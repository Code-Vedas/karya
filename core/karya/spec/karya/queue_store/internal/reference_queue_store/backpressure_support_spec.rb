# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::Internal::ReferenceQueueStore::Internal::BackpressureSupport' do
  let(:store) { Karya::QueueStore::InMemory.new }
  let(:described_class) do
    store.class
         .ancestors
         .find { |ancestor| ancestor.respond_to?(:name) && ancestor.name == 'Karya::QueueStore::Internal::ReferenceQueueStore' }
         .const_get(:Internal, false)
         .const_get(:BackpressureSupport, false)
  end
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

  it 'yields a distinct explicit scope key after queue and handler keys' do
    explicit_scope = Karya::Backpressure::Scope.new(kind: :custom, value: 'tenant-acme')

    keys = []
    described_class.each_scope_key(stored_job, explicit_scope) { |scope_key| keys << scope_key }

    expect(keys).to eq(['queue:billing', 'handler:billing_sync', explicit_scope.key])
  end

  it 'skips the explicit scope key when no distinct scope is provided' do
    keys = []
    described_class.each_scope_key(stored_job, nil) { |scope_key| keys << scope_key }

    expect(keys).to eq(['queue:billing', 'handler:billing_sync'])
  end

  it 'removes orphaned rate-limit admission keys during stale-pruning maintenance' do
    state.rate_limit_admissions_by_key['orphan'] = [Time.utc(2026, 3, 27, 12, 0, 0)]

    store.send(:prune_stale_rate_limit_admissions, Time.utc(2026, 3, 27, 12, 0, 20))

    expect(state.rate_limit_admissions_by_key).to eq({})
  end
end
