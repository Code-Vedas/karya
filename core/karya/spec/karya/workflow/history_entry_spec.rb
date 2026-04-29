# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Workflow::HistoryEntry do
  let(:occurred_at) { Time.utc(2026, 4, 29, 12, 0, 0) }

  it 'normalizes workflow history attributes and defaults' do
    entry = described_class.new(
      kind: :step,
      action: :running,
      occurred_at:,
      workflow_id: :invoice_closeout,
      batch_id: :batch_one,
      step_id: :capture,
      job_id: :job_capture,
      child_batch_id: :child_batch,
      details: { 'reason' => 'operator replay', 'attempt' => 2 }
    )

    expect(entry.kind).to eq(:step)
    expect(entry.action).to eq('running')
    expect(entry.workflow_id).to eq('invoice_closeout')
    expect(entry.workflow_family).to eq('invoice_closeout')
    expect(entry.workflow_version).to eq('v1')
    expect(entry.batch_id).to eq('batch_one')
    expect(entry.step_id).to eq('capture')
    expect(entry.job_id).to eq('job_capture')
    expect(entry.child_batch_id).to eq('child_batch')
    expect(entry.details).to eq({ 'reason' => 'operator replay', 'attempt' => 2 })
    expect(entry).to be_frozen
  end

  it 'rejects unsupported history kinds' do
    expect do
      described_class.new(
        kind: :unsupported,
        action: :running,
        occurred_at:,
        workflow_id: :invoice_closeout,
        batch_id: :batch_one
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'kind must be a supported workflow history kind')
  end

  it 'rejects unknown keywords and invalid timestamps' do
    expect do
      described_class.new(
        kind: :step,
        action: :running,
        occurred_at:,
        workflow_id: :invoice_closeout,
        batch_id: :batch_one,
        unexpected: :value
      )
    end.to raise_error(ArgumentError, 'unknown keyword: :unexpected')

    expect do
      described_class.new(
        kind: :step,
        action: :running,
        occurred_at: '2026-04-29T12:00:00Z',
        workflow_id: :invoice_closeout,
        batch_id: :batch_one
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'occurred_at must be a Time')
  end

  it 'rejects invalid kind and details shapes' do
    expect do
      described_class.new(
        kind: 123,
        action: :running,
        occurred_at:,
        workflow_id: :invoice_closeout,
        batch_id: :batch_one
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'kind must be a Symbol or String')

    expect do
      described_class.new(
        kind: :step,
        action: :running,
        occurred_at:,
        workflow_id: :invoice_closeout,
        batch_id: :batch_one,
        details: []
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'details must be a Hash')

    expect do
      described_class.new(
        kind: :step,
        action: :running,
        occurred_at:,
        workflow_id: :invoice_closeout,
        batch_id: :batch_one,
        details: { reason: 'operator replay' }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'details keys must be Strings')

    expect do
      described_class.new(
        kind: :step,
        action: :running,
        occurred_at:,
        workflow_id: :invoice_closeout,
        batch_id: :batch_one,
        details: { 'reason' => Object.new }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'details values must be JSON-compatible')
  end

  it 'rejects oversized and non-json-encodable details payloads' do
    expect do
      described_class.new(
        kind: :step,
        action: :running,
        occurred_at:,
        workflow_id: :invoice_closeout,
        batch_id: :batch_one,
        details: { 'payload' => 'x' * ((16 * 1024) + 1) }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'details exceeds 16384 bytes')

    expect do
      described_class.new(
        kind: :step,
        action: :running,
        occurred_at:,
        workflow_id: :invoice_closeout,
        batch_id: :batch_one,
        details: { 'payload' => Float::NAN }
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'details must be JSON-encodable')
  end
end
