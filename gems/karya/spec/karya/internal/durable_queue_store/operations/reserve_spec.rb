# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::Operations::Reserve do
  include_context 'with durable queue-store operations spec support'

  it 'returns nil when paused queues and policy gates block every candidate' do
    gate_data = reserve_gate_rows
    reserve = described_class.new(
      store: reserve_gate_store,
      request: {
        worker_id: 'worker-1',
        lease_duration: 30,
        now:,
        queues: %w[paused billing],
        handler_names: ['ProcessInvoice']
      },
      operation_name: :reserve
    )

    selector = described_class::CandidateSelector.new(
      operation: reserve,
      rows: gate_data.fetch(:rows),
      reserve_request: reserve.send(:normalized_reserve_request)
    )

    expect(selector.send(:paused_queues)).to eq(['paused'])
    expect(selector.call).to be_nil
    expect(reserve.call(context: context(rows: gate_data.fetch(:rows))).value).to be_nil
  end

  it 'reserves the first visible candidate and persists reservation rows' do
    queued_job = job(id: 'job-1', state: :queued)
    retry_pending_job = job(id: 'job-2', state: :retry_pending, next_retry_at: now - 5)
    rows = empty_rows.merge(
      jobs: [job_row(queued_job), job_row(retry_pending_job)],
      queue_entries: [
        queue_entry_row(queued_job, insertion_sequence: 2),
        queue_entry_row(retry_pending_job, insertion_sequence: 1)
      ]
    )
    reserve = described_class.new(
      store:,
      request: {
        worker_id: 'worker-1',
        lease_duration: 30,
        now:,
        queues: ['billing']
      },
      operation_name: :reserve
    )

    result = reserve.call(context: context(rows:))

    expect(result.value.job_id).to eq('job-2')
    expect(result.mutation_plan.inserts.fetch(:reservations).length).to eq(1)
    expect(result.mutation_plan.deletes.fetch(:queue_entries).map { |row| row.fetch(:job_id) }).to eq(['job-2'])
    expect(result.mutation_plan.updates.fetch(:jobs).first.fetch(:state)).to eq('reserved')
  end

  it 'raises duplicate reservation token errors on reserve' do
    gate_data = reserve_gate_rows
    duplicate_store = reserve_gate_store.dup
    duplicate_store.define_singleton_method(:token_generator) { -> { 'dup-token' } }
    duplicate_reserve = described_class.new(
      store: duplicate_store,
      request: {
        worker_id: 'worker-1',
        lease_duration: 30,
        now:,
        queues: ['billing']
      },
      operation_name: :reserve
    )
    duplicate_context = context(
      rows: empty_rows.merge(
        jobs: [job_row(gate_data.fetch(:token_job))],
        queue_entries: [queue_entry_row(gate_data.fetch(:token_job))],
        reservations: [reservation_row(job: gate_data.fetch(:token_job), token: 'dup-token:1', phase: :reserved)]
      )
    )

    expect do
      duplicate_reserve.call(context: duplicate_context)
    end.to raise_error(Karya::DuplicateReservationTokenError, /dup-token:1/)
  end
end
