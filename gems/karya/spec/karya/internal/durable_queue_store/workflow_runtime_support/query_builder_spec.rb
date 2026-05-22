# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Karya::Internal::DurableQueueStore::WorkflowRuntimeSupport::QueryBuilder do
  include_context 'with durable queue-store operations spec support'

  it 'builds query results and current step values from workflow snapshots' do
    snapshot = Karya::Internal::DurableQueueStore::Operations::WorkflowSnapshot.new(
      store:,
      request: { batch_id: :helper_batch, now: },
      operation_name: :workflow_snapshot
    ).call(
      context: context(
        rows: workflow_enqueue_rows(
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
      )
    ).value

    expect(described_class.new(snapshot:, query: :state, queried_at: now).build.value).to eq(snapshot.state)
    expect(described_class.new(snapshot:, query: :'current-steps', queried_at: now).value).to eq(['approve'])

    expect do
      described_class.new(snapshot:, query: :unsupported, queried_at: now).value
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /unsupported workflow query/)
  end
end
