# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::PolicyStateRecord do
  it 'normalizes policy scope prefixes and fallback custom scopes' do
    expect(described_class.scope_components('')).to eq(['queue', ''])
    expect(described_class.scope_components('queue:billing')).to eq(%w[queue billing])
    expect(described_class.scope_components('handler:sync')).to eq(%w[handler sync])
    expect(described_class.scope_components('tenant:acme')).to eq(%w[tenant acme])
    expect(described_class.scope_components('workflow:closeout')).to eq(%w[workflow closeout])
    expect(described_class.scope_components('custom:scope')).to eq(%w[custom scope])
    expect(described_class.scope_components('no-separator')).to eq(%w[custom no-separator])
  end

  it 'stringifies nested symbol, array, and hash payload members' do
    payload = described_class.stringify_payload(
      kind: :half_open,
      admissions: [:queued, { nested: :running }],
      metadata: { worker: 'a' }
    )

    expect(payload).to eq(
      'kind' => 'half_open',
      'admissions' => ['queued', { 'nested' => 'running' }],
      'metadata' => { 'worker' => 'a' }
    )
  end
end
