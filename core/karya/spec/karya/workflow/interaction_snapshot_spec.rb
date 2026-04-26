# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Workflow::InteractionSnapshot do
  let(:received_at) { Time.utc(2026, 4, 26, 12, 0, 0) }

  it 'normalizes, deep-freezes, and exposes interaction data' do
    mutable_string = +'ops'
    snapshot = described_class.new(
      kind: 'signal',
      name: ' manager-approved ',
      payload: {
        'approved_by' => mutable_string,
        'attempts' => [1, 2],
        'metadata' => { 'source' => 'console' }
      },
      received_at:
    )
    mutable_string.replace('changed')

    expect(snapshot).to have_attributes(
      kind: :signal,
      name: 'manager-approved',
      payload: {
        'approved_by' => 'ops',
        'attempts' => [1, 2],
        'metadata' => { 'source' => 'console' }
      },
      received_at:
    )
    expect(snapshot).to be_frozen
    expect(snapshot.payload).to be_frozen
    expect(snapshot.payload.fetch('approved_by')).to be_frozen
    expect(snapshot.payload.fetch('attempts')).to be_frozen
    expect(snapshot.payload.fetch('metadata')).to be_frozen
  end

  it 'rejects invalid kinds and payload shapes' do
    expect do
      described_class.new(kind: :unknown, name: :signal, payload: {}, received_at:)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'kind must be :signal or :event')
    expect do
      described_class.new(kind: 123, name: :signal, payload: {}, received_at:)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'kind must be :signal or :event')
    expect do
      described_class.new(kind: :signal, name: :signal, payload: {}, received_at: '2026-04-26T12:00:00Z')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'received_at must be a Time')
    expect do
      described_class.new(kind: :signal, name: :signal, payload: 'payload', received_at:)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'payload must be a Hash')
    expect do
      described_class.new(kind: :signal, name: :signal, payload: { source: 'console' }, received_at:)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'payload keys must be Strings')
    expect do
      described_class.new(kind: :signal, name: :signal, payload: { 'received_at' => Time.now }, received_at:)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'payload values must be JSON-compatible')
    expect do
      described_class.new(kind: :signal, name: :signal, payload: { 'message' => 'x' * (16 * 1024) }, received_at:)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'payload exceeds 16384 bytes')
    expect do
      described_class.new(kind: :signal, name: '   ', payload: {}, received_at:)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'name must be present')
  end

  it 'rejects unknown attributes' do
    expect do
      described_class.new(
        kind: :event,
        name: :payment_received,
        payload: {},
        received_at:,
        unexpected: true
      )
    end.to raise_error(ArgumentError, 'unknown keyword: :unexpected')
  end
end
