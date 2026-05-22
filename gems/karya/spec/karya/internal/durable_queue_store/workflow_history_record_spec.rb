# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::WorkflowHistoryRecord do
  let(:occurred_at) { Time.utc(2026, 5, 23, 12, 0, 0) }
  let(:entry) do
    Struct.new(:kind, :action, :workflow_id, :workflow_family, :workflow_version, :step_id, :job_id, :child_batch_id, :details, :occurred_at).new(
      :step, :started, 'wf-1', 'billing', 'v1', 'step-1', 'job-1', 'child-1', { 'reason' => 'ok' }, occurred_at
    )
  end

  it 'serializes one workflow history row' do
    row = described_class.new(namespace: 'tenant', batch_id: 'batch-1', sequence: 3, entry:).to_h

    expect(row).to include(
      namespace: 'tenant',
      batch_id: 'batch-1',
      sequence: 3,
      entry_type: 'step',
      occurred_at:
    )
    expect(Karya::Internal::DurableQueueStore::PayloadCodec.decode(row.fetch(:details_payload))).to eq(
      'action' => 'started',
      'workflow_id' => 'wf-1',
      'workflow_family' => 'billing',
      'workflow_version' => 'v1',
      'step_id' => 'step-1',
      'job_id' => 'job-1',
      'child_batch_id' => 'child-1',
      'details' => { 'reason' => 'ok' }
    )
  end
end
