# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Workflow::HistorySnapshot do
  let(:captured_at) { Time.utc(2026, 4, 29, 12, 0, 0) }

  it 'normalizes workflow history snapshots' do
    entry = Karya::Workflow::HistoryEntry.new(
      kind: :workflow,
      action: :workflow_registered,
      occurred_at: captured_at - 1,
      workflow_id: :invoice_closeout,
      batch_id: :batch_one
    )

    snapshot = described_class.new(
      workflow_id: :invoice_closeout,
      batch_id: :batch_one,
      captured_at:,
      entries: [entry]
    )

    expect(snapshot.workflow_id).to eq('invoice_closeout')
    expect(snapshot.workflow_family).to eq('invoice_closeout')
    expect(snapshot.workflow_version).to eq('v1')
    expect(snapshot.batch_id).to eq('batch_one')
    expect(snapshot.entries).to eq([entry])
    expect(snapshot.entries).to be_frozen
    expect(snapshot).to be_frozen
  end

  it 'rejects unknown keywords and invalid timestamps' do
    entry = Karya::Workflow::HistoryEntry.new(
      kind: :workflow,
      action: :workflow_registered,
      occurred_at: captured_at - 1,
      workflow_id: :invoice_closeout,
      batch_id: :batch_one
    )

    expect do
      described_class.new(
        workflow_id: :invoice_closeout,
        batch_id: :batch_one,
        captured_at:,
        entries: [entry],
        unexpected: :value
      )
    end.to raise_error(ArgumentError, 'unknown keyword: :unexpected')

    expect do
      described_class.new(
        workflow_id: :invoice_closeout,
        batch_id: :batch_one,
        captured_at: '2026-04-29T12:00:00Z',
        entries: [entry]
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'captured_at must be a Time')
  end

  it 'rejects invalid entry lists' do
    entry = Karya::Workflow::HistoryEntry.new(
      kind: :workflow,
      action: :workflow_registered,
      occurred_at: captured_at - 1,
      workflow_id: :invoice_closeout,
      batch_id: :batch_one
    )

    expect do
      described_class.new(
        workflow_id: :invoice_closeout,
        batch_id: :batch_one,
        captured_at:,
        entries: entry
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'entries must be an Array of Karya::Workflow::HistoryEntry')

    expect do
      described_class.new(
        workflow_id: :invoice_closeout,
        batch_id: :batch_one,
        captured_at:,
        entries: [entry, Object.new]
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'entries must be Karya::Workflow::HistoryEntry instances')
  end
end
