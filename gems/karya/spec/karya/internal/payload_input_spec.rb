# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::PayloadInput do
  let(:error_class) { Karya::InvalidOutboundEventError }
  let(:payload_message) { 'payload must be a Hash' }
  let(:mixed_payload_message) { 'payload must be a Hash when keyword payload is also given' }

  it 'returns keyword payloads when no positional payload is given' do
    payload = described_class.new(described_class::ABSENT, { worker_id: 'worker-1' }, payload_given: false, error_class:, mixed_payload_message:)

    expect(payload.to_h).to eq(worker_id: 'worker-1')
  end

  it 'uses a unique sentinel instead of a collidable symbol payload value' do
    expect(described_class::ABSENT).not_to be_a(Symbol)

    payload = described_class.new(:__payload_input_absent__, {}, payload_given: true, error_class:, mixed_payload_message:)

    expect { payload.to_h }.to raise_error(Karya::InvalidOutboundEventError, payload_message)
  end

  it 'returns the positional payload unchanged when no keyword payloads are given' do
    positional_payload = { worker_id: 'worker-1' }.freeze
    payload = described_class.new(positional_payload, {}, payload_given: true, error_class:, mixed_payload_message:)

    expect(payload.to_h).to be(positional_payload)
  end

  it 'merges positional and keyword payloads when both are hashes' do
    payload = described_class.new({ worker_id: 'worker-1' }, { queue: 'billing' }, payload_given: true, error_class:, mixed_payload_message:)

    expect(payload.to_h).to eq(worker_id: 'worker-1', queue: 'billing')
  end

  it 'rejects non-hash positional payloads when keyword payloads are also given' do
    payload = described_class.new('bad', { worker_id: 'worker-1' }, payload_given: true, error_class:, mixed_payload_message:)

    expect { payload.to_h }.to raise_error(Karya::InvalidOutboundEventError, mixed_payload_message)
  end

  it 'rejects non-hash positional payloads when no keyword payloads are given' do
    payload = described_class.new('bad', {}, payload_given: true, error_class:, mixed_payload_message:)

    expect { payload.to_h }.to raise_error(Karya::InvalidOutboundEventError, payload_message)
  end
end
