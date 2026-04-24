# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::ReserveScanState' do
  let(:internal) { Karya::QueueStore::InMemory.const_get(:Internal, false) }
  let(:described_class) { internal.const_get(:ReserveScanState, false) }
  let(:store_state) { internal.const_get(:StoreState, false).new(expired_tombstone_limit: 8) }
  let(:reservation_class) { Karya::Reservation }
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }
  let(:job) do
    Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      concurrency_key: 'billing',
      rate_limit_key: 'billing',
      state: :queued,
      created_at:,
      updated_at: created_at + 1
    )
  end
  let(:policy_set) do
    Karya::Backpressure::PolicySet.new(
      concurrency: {
        'queue:billing' => { limit: 1 }
      },
      rate_limits: {
        'queue:billing' => { limit: 1, period: 60 }
      }
    )
  end

  before do
    store_state.jobs_by_id[job.id] = job
    store_state.reservations_by_token['lease-1'] = reservation_class.new(
      token: 'lease-1',
      job_id: job.id,
      queue: job.queue,
      worker_id: 'worker-1',
      reserved_at: created_at + 2,
      expires_at: created_at + 32
    )
    store_state.rate_limit_admissions_by_key['queue:billing'] = [created_at + 2]
  end

  it 'detects concurrency blocking from active reservations' do
    scan_state = described_class.new(policy_set:, state: store_state)

    expect(scan_state.concurrency_blocked?(job)).to be(true)
  end

  it 'detects rate limits from tracked admissions' do
    scan_state = described_class.new(policy_set:, state: store_state)

    expect(scan_state.rate_limited?(job)).to be(true)
  end
end
