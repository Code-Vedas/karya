# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::JobRecord do
  let(:created_at) { Time.utc(2026, 5, 22, 15, 30, 0) }
  let(:retry_policy) do
    Karya::RetryPolicy.new(max_attempts: 5, base_delay: 2, multiplier: 3, jitter_strategy: :equal)
  end
  let(:concurrency_scope) { Karya::Backpressure::Scope.from({ kind: :tenant, value: 'acme' }) }
  let(:job) do
    Karya::Job.new(
      id: 'job-123',
      queue: 'billing',
      handler: 'sync_billing',
      arguments: { customer_id: 'cus_123', tags: %w[priority vip] },
      priority: 9,
      state: :retry_pending,
      attempt: 2,
      created_at:,
      enqueued_at: created_at + 15,
      updated_at: created_at + 30,
      next_retry_at: created_at + 60,
      retry_policy:,
      execution_timeout: 45,
      concurrency_scope:,
      idempotency_key: 'bill:cus_123',
      uniqueness_key: 'workflow:invoice-closeout',
      uniqueness_scope: :active,
      failure_classification: :error
    )
  end

  it 'projects one canonical job into the durable jobs table shape' do
    row = described_class.new(namespace: 'primary', job:).to_h
    codec = Karya::QueueStore::Internal::StateSnapshot

    expect(row).to include(
      namespace: 'primary',
      job_id: 'job-123',
      queue: 'billing',
      handler: 'sync_billing',
      priority: 9,
      state: 'retry_pending',
      attempt: 2,
      visible_at: created_at + 60,
      created_at:,
      enqueued_at: created_at + 15,
      updated_at: created_at + 30,
      execution_timeout_seconds: 45,
      idempotency_key: 'bill:cus_123',
      uniqueness_key: 'workflow:invoice-closeout',
      uniqueness_scope: 'active',
      failure_classification: 'error'
    )
    expect(codec.load_payload(row.fetch(:arguments_payload))).to eq({ 'customer_id' => 'cus_123', 'tags' => %w[priority vip] })
    expect(codec.load_payload(row.fetch(:retry_policy_payload))).to have_attributes(max_attempts: 5, base_delay: 2, multiplier: 3)
    expect(codec.load_payload(row.fetch(:concurrency_scope))).to have_attributes(kind: :tenant, value: 'acme')
    expect(codec.load_payload(row.fetch(:lifecycle_extensions_payload))).to include(
      state_names: [],
      terminal_state_names: [],
      transitions: {}
    )
  end
end
