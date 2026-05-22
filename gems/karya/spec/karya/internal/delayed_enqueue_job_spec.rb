# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DelayedEnqueueJob do
  let(:created_at) { Time.utc(2026, 5, 21, 12, 0, 0) }
  let(:scheduled_at) { Time.utc(2026, 5, 21, 12, 6, 0) }
  let(:dispatched_at) { Time.utc(2026, 5, 21, 12, 6, 30) }

  it 'serializes and deserializes delayed enqueue requests through the durable payload codec' do
    payload = described_class.serialize_request(
      queue: 'billing',
      handler: 'sync_billing',
      arguments: { 'requested_at' => created_at, 'tags' => %w[priority vip] },
      job_id: 'job-1',
      created_at:,
      scheduled_at:
    )

    expect(described_class.deserialize_request(payload)).to eq(
      'queue' => 'billing',
      'handler' => 'sync_billing',
      'arguments' => { 'requested_at' => created_at, 'tags' => %w[priority vip] },
      'job_id' => 'job-1',
      'created_at' => created_at,
      'scheduled_at' => scheduled_at
    )
  end

  it 're-enqueues the wrapped Karya job with preserved created_at and refreshed enqueued_at' do
    payload = described_class.serialize_request(
      queue: 'billing',
      handler: 'sync_billing',
      arguments: { 'requested_at' => created_at },
      job_id: 'job-1',
      created_at:,
      scheduled_at:
    )
    allow(Time).to receive(:now).and_return(dispatched_at)
    allow(Karya).to receive(:enqueue)

    described_class.perform(payload)

    expect(Karya).to have_received(:enqueue).with(
      queue: 'billing',
      handler: 'sync_billing',
      arguments: { 'requested_at' => created_at },
      now: dispatched_at,
      job_id: 'job-1',
      created_at:,
      enqueued_at: dispatched_at
    )
  end
end
