# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Hooks do
  around do |example|
    described_class.reset!
    example.run
  ensure
    described_class.reset!
  end

  it 'registers listeners, dispatches them in registration order, and exposes a snapshot of listeners' do
    calls = []
    first = ->(payload) { calls << ['first', payload.fetch('event')] }
    second = ->(payload) { calls << ['second', payload.fetch('event')] }

    described_class.register(:runtime_start, first)
    described_class.register(:runtime_start, second)
    described_class.dispatch(:runtime_start, payload: { 'event' => 'runtime_start' })

    expect(calls).to eq([
                          %w[first runtime_start],
                          %w[second runtime_start]
                        ])
    expect(described_class.listeners(:runtime_start)).to eq([first, second])
  end

  it 'supports block registration and authorization decision overrides' do
    described_class.register(:operator_authorization) { |payload| !payload.fetch('authorized') }
    described_class.register(:operator_authorization) { nil }

    expect(described_class.dispatch_authorization(payload: { 'framework' => 'rails' }, default: true)).to be(false)
  end

  it 'keeps the default authorization decision when no hooks are registered' do
    expect(described_class.dispatch_authorization(payload: { 'framework' => 'rails' }, default: true)).to be(true)
  end

  it 'rejects unsupported hook events and non-callable registrations' do
    expect do
      described_class.register(:unknown_event, ->(_payload) {})
    end.to raise_error(ArgumentError, /unsupported Karya hook event/)

    expect do
      described_class.register(:runtime_start)
    end.to raise_error(ArgumentError, 'Karya hook must respond to #call')

    expect do
      described_class.register(:runtime_start, Object.new)
    end.to raise_error(ArgumentError, 'Karya hook must respond to #call')
  end

  it 'clears registrations when reset is requested' do
    described_class.register(:runtime_stop, ->(_payload) {})

    described_class.reset!

    expect(described_class.listeners(:runtime_stop)).to eq([])
  end
end
