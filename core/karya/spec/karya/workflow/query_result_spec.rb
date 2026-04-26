# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Workflow::QueryResult do
  let(:queried_at) { Time.utc(2026, 4, 26, 12, 0, 0) }

  it 'normalizes supported workflow queries' do
    state = described_class.new(query: ' state ', value: :running, queried_at:)
    current_step = described_class.new(query: :'current-step', value: ' capture_payment ', queried_at:)
    current_steps = described_class.new(query: 'current-steps', value: %i[capture_payment emit_receipt], queried_at:)

    expect(state).to have_attributes(query: 'state', value: :running, queried_at:)
    expect(current_step).to have_attributes(query: 'current-step', value: 'capture_payment', queried_at:)
    expect(current_steps).to have_attributes(query: 'current-steps', value: %w[capture_payment emit_receipt], queried_at:)
    expect(current_steps.value).to be_frozen
  end

  it 'allows current-step queries to return nil' do
    result = described_class.new(query: 'current-step', value: nil, queried_at:)

    expect(result.value).to be_nil
  end

  it 'rejects unsupported query names and invalid values' do
    expect do
      described_class.new(query: 'unknown', value: :running, queried_at:)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'unsupported workflow query "unknown"')
    expect do
      described_class.new(query: 'state', value: 'running', queried_at:)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'workflow query "state" must return a Symbol')
    expect do
      described_class.new(query: 'current-steps', value: 'capture_payment', queried_at:)
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'workflow query "current-steps" must return an Array')
  end

  it 'rejects invalid timestamps and unsupported low-level query values' do
    expect do
      described_class.new(query: 'state', value: :running, queried_at: '2026-04-26T12:00:00Z')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'queried_at must be a Time')

    value = described_class.const_get(:Value, false)
    expect do
      value.new('unsupported', nil).normalize
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'unsupported workflow query "unsupported"')
  end
end
