# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::SqlStateStore do
  let(:state_store_class) do
    Class.new(described_class) do
      private

      def table_names
        {
          metadata: 'metadata',
          queue_entries: 'queue_entries',
          jobs: 'jobs',
          reservations: 'reservations',
          policy_state: 'policy_state',
          workflow_batches: 'workflow_batches',
          workflow_steps: 'workflow_steps',
          workflow_interactions: 'workflow_interactions',
          workflow_history: 'workflow_history'
        }
      end
    end
  end
  let(:table_names) do
    {
      metadata: 'metadata',
      queue_entries: 'queue_entries',
      jobs: 'jobs',
      reservations: 'reservations',
      policy_state: 'policy_state',
      workflow_batches: 'workflow_batches',
      workflow_steps: 'workflow_steps',
      workflow_interactions: 'workflow_interactions',
      workflow_history: 'workflow_history'
    }
  end
  let(:state_store) { state_store_class.new(table_names:) }

  it 'loads workflow operation rows and raises on abstract adapter hooks' do
    workflow_store = state_store_class.new(table_names:)
    workflow_rows =
      workflow_store.tap do |store|
        allow(store).to receive_messages(select_all: [], placeholder: '?')
      end.fetch_rows_for_operation(operation_name: :enqueue_workflow, namespace: 'spec', request: {})

    expect(workflow_rows).to include(:workflow_batches, :workflow_steps, :workflow_interactions, :workflow_history, :policy_state)
    expect do
      workflow_store.fetch_rows_for_operation(operation_name: :missing, namespace: 'spec', request: {})
    end.to raise_error(NotImplementedError, /:missing/)
    expect do
      state_store.send(:select_all, 'SELECT 1', [])
    end.to raise_error(NotImplementedError, /select_all/)
    expect do
      state_store.send(:execute_write, 'UPDATE', [])
    end.to raise_error(NotImplementedError, /execute_write/)
    expect do
      state_store.send(:placeholder, 1)
    end.to raise_error(NotImplementedError, /placeholder/)
  end

  it 'loads duplicate enqueue-many queue rows only once per queue' do
    job_class = Struct.new(:queue)
    allow(state_store).to receive(:base_uniqueness_rows).and_return(jobs: [], reservations: [], queue_entries: [])
    allow(state_store).to receive(:select_rows).with(:queue_entries, namespace: 'spec', queue: 'billing').and_return([{ job_id: 'job-1' }])

    rows = state_store.fetch_rows_for_operation(
      operation_name: :enqueue_many,
      namespace: 'spec',
      request: { jobs: [job_class.new('billing'), job_class.new('billing')] }
    )

    expect(rows.fetch(:queue_entries)).to eq([{ job_id: 'job-1' }])
    expect(state_store).to have_received(:select_rows).once
    expect(state_store.send(:job_ids_from_rows, rows.fetch(:queue_entries))).to eq(['job-1'])
  end
end
