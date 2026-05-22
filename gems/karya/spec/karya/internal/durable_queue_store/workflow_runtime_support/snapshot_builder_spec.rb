# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Karya::Internal::DurableQueueStore::WorkflowRuntimeSupport::SnapshotBuilder do
  include_context 'with durable queue-store operations spec support'

  let(:helper) { helper_class.new(store:, request: {}) }

  it 'delegates snapshot and query wrapper methods to the extracted builders' do
    rows = workflow_enqueue_rows(
      definition: Karya::Workflow.define(:approval) do
        step :approve, handler: :approve, wait_for_approval: :approve_signal
        step :signal_step, handler: :signal_step, wait_for_signal: :ready_signal, depends_on: :approve
      end,
      jobs_by_step_id: {
        approve: job(id: 'job-approve', state: :submission, handler: :approve),
        signal_step: job(id: 'job-signal', state: :submission, handler: :signal_step)
      },
      batch_id: :helper_batch
    )

    snapshot = helper.send(:build_workflow_snapshot, rows:, batch_id: 'helper_batch', now: now, cache: {}, visiting: {})
    batch = helper.send(:workflow_batch_from_rows, rows, 'helper_batch')

    expect(helper.send(:workflow_snapshot_jobs, rows, 'helper_batch', batch).map(&:id)).to eq(%w[job-approve job-signal])
    expect(helper.send(:workflow_query_result, snapshot:, query: :'current-step', queried_at: now).value).to eq('approve')
    expect(helper.send(:workflow_query_value, snapshot, :'current-steps')).to eq(['approve'])
    expect(helper.send(:current_workflow_step_ids, snapshot.steps)).to eq(['approve'])
    expect(helper.send(:workflow_state_for_batch, rows, 'helper_batch', now, cache: {}, visiting: {})).to eq(snapshot.state)
  end
end
