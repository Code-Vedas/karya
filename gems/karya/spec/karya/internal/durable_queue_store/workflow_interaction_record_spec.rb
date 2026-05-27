# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::WorkflowInteractionRecord do
  let(:received_at) { Time.utc(2026, 5, 23, 12, 0, 0) }
  let(:interaction) { Struct.new(:kind, :name, :payload, :received_at).new(:signal, 'approve', { 'step' => 'a' }, received_at) }

  it 'serializes one workflow interaction row' do
    row = described_class.new(namespace: 'tenant', batch_id: 'batch-1', sequence: 2, interaction:).to_h

    expect(row).to include(
      namespace: 'tenant',
      batch_id: 'batch-1',
      sequence: 2,
      kind: 'signal',
      name: 'approve',
      received_at:
    )
    expect(Karya::Internal::DurableQueueStore::PayloadCodec.decode(row.fetch(:payload))).to eq('step' => 'a')
  end
end
