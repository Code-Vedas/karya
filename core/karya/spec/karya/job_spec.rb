# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Job do
  let(:created_at) { Time.utc(2026, 3, 26, 12, 0, 0) }
  let(:updated_at) { Time.utc(2026, 3, 26, 12, 5, 0) }
  let(:retry_policy) { Karya::RetryPolicy.new(max_attempts: 3, base_delay: 5, multiplier: 2) }
  let(:next_retry_at) { Time.utc(2026, 3, 26, 12, 10, 0) }

  describe '#initialize' do
    it 'builds an immutable canonical job with normalized fields' do
      job = described_class.new(
        id: :job123,
        queue: 'billing',
        handler: :billing_sync,
        arguments: { 'account_id' => 42, metadata: { source: 'sync' }, tags: ['vip'] },
        priority: 5,
        concurrency_key: 'account-42',
        rate_limit_key: 'partner-api',
        retry_policy: retry_policy,
        state: 'retry-pending',
        attempt: 2,
        created_at:,
        updated_at:,
        next_retry_at: next_retry_at
      )

      expect(job.id).to eq('job123')
      expect(job.queue).to eq('billing')
      expect(job.handler).to eq('billing_sync')
      expect(job.id).to be_frozen
      expect(job.queue).to be_frozen
      expect(job.handler).to be_frozen
      expect(job.arguments).to eq('account_id' => 42, 'metadata' => { 'source' => 'sync' }, 'tags' => ['vip'])
      expect(job.arguments).to be_frozen
      expect(job.arguments['metadata']).to be_frozen
      expect(job.arguments['tags']).to be_frozen
      expect(job.priority).to eq(5)
      expect(job.concurrency_key).to eq('account-42')
      expect(job.rate_limit_key).to eq('partner-api')
      expect(job.retry_policy).to eq(retry_policy)
      expect(job.state).to eq(:retry_pending)
      expect(job.attempt).to eq(2)
      expect(job.created_at).to eq(created_at)
      expect(job.updated_at).to eq(updated_at)
      expect(job.next_retry_at).to eq(next_retry_at)
      expect(job.created_at).to be_frozen
      expect(job.updated_at).to be_frozen
      expect(job.next_retry_at).to be_frozen
      expect(job).to be_frozen
    end

    it 'uses an explicit lifecycle registry when provided' do
      lifecycle = Karya::JobLifecycle::Registry.new
      lifecycle.register_state('archived', terminal: true)
      lifecycle.register_transition(from: :queued, to: 'archived')

      job = described_class.new(
        id: 'job123',
        queue: 'billing',
        handler: 'billing_sync',
        state: :queued,
        lifecycle:,
        created_at:
      )

      transitioned_job = job.transition_to('archived', updated_at:)

      expect(job.can_transition_to?('archived')).to be(true)
      expect(transitioned_job.state).to eq('archived')
      expect(transitioned_job.terminal?).to be(true)
    end
  end

  describe '#can_transition_to?' do
    it 'returns true for valid transitions and false for invalid ones' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        state: :queued,
        created_at:
      )

      expect(job.can_transition_to?(:reserved)).to be(true)
      expect(job.can_transition_to?(:running)).to be(false)
    end

    it 'returns false for unknown target states instead of raising' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        state: :queued,
        created_at:
      )

      expect(job.can_transition_to?(:unknown)).to be(false)
    end
  end

  describe '#transition_to' do
    it 'returns a new immutable job instance in the target state' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        state: :reserved,
        created_at:
      )

      transitioned_job = job.transition_to(:running, updated_at:)

      expect(transitioned_job).not_to be(job)
      expect(transitioned_job.state).to eq(:running)
      expect(transitioned_job.updated_at).to eq(updated_at)
      expect(job.state).to eq(:reserved)
    end

    it 'rejects invalid transitions' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        state: :succeeded,
        created_at:
      )

      expect { job.transition_to(:queued, updated_at:) }
        .to raise_error(Karya::JobLifecycle::InvalidJobTransitionError, /Cannot transition/)
    end

    it 'validates the transition timestamp on the new job' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        state: :running,
        created_at:
      )

      expect { job.transition_to(:cancelled, updated_at: 'later') }
        .to raise_error(Karya::InvalidJobAttributeError, /updated_at must be a Time/)
    end

    it 'reuses already-normalized frozen scalar arguments on transition' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        arguments: { message: 'hello', scheduled_at: Time.utc(2026, 3, 26, 12, 30, 0) },
        state: :reserved,
        created_at:
      )

      transitioned_job = job.transition_to(:running, updated_at:)

      expect(transitioned_job.arguments['message']).to equal(job.arguments['message'])
      expect(transitioned_job.arguments['scheduled_at']).to equal(job.arguments['scheduled_at'])
    end

    it 'reuses an already-normalized frozen argument graph on transition' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        arguments: {
          metadata: { source: 'sync' },
          tags: ['vip']
        },
        state: :reserved,
        created_at:
      )

      transitioned_job = job.transition_to(:running, updated_at:)

      expect(transitioned_job.arguments).to equal(job.arguments)
      expect(transitioned_job.arguments['metadata']).to equal(job.arguments['metadata'])
      expect(transitioned_job.arguments['tags']).to equal(job.arguments['tags'])
    end

    it 'preserves priority and policy keys across transitions' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        priority: 9,
        concurrency_key: 'account-9',
        rate_limit_key: 'partner-api',
        retry_policy: retry_policy,
        state: :reserved,
        created_at:,
        next_retry_at: next_retry_at
      )

      transitioned_job = job.transition_to(:running, updated_at:)

      expect(transitioned_job.priority).to eq(9)
      expect(transitioned_job.concurrency_key).to eq('account-9')
      expect(transitioned_job.rate_limit_key).to eq('partner-api')
      expect(transitioned_job.retry_policy).to eq(retry_policy)
      expect(transitioned_job.next_retry_at).to eq(next_retry_at)
    end

    it 'allows overriding retry metadata during transition' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        retry_policy: retry_policy,
        state: :failed,
        attempt: 1,
        created_at:
      )

      transitioned_job = job.transition_to(:retry_pending, updated_at:, next_retry_at: next_retry_at, retry_policy: retry_policy)

      expect(transitioned_job.retry_policy).to eq(retry_policy)
      expect(transitioned_job.next_retry_at).to eq(next_retry_at)
    end

    it 'freezes internal component structs to preserve immutability' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        priority: 9,
        concurrency_key: 'account-9',
        rate_limit_key: 'partner-api',
        state: :reserved,
        created_at:
      )

      expect(job.instance_variable_get(:@identity)).to be_frozen
      expect(job.instance_variable_get(:@scheduling)).to be_frozen
      expect(job.instance_variable_get(:@lifecycle_state)).to be_frozen
    end
  end

  describe '#terminal?' do
    it 'returns true for terminal states and false otherwise' do
      succeeded_job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        state: :succeeded,
        created_at:
      )
      queued_job = described_class.new(
        id: 'job_456',
        queue: 'billing',
        handler: 'billing_sync',
        state: :queued,
        created_at:
      )

      expect(succeeded_job.terminal?).to be(true)
      expect(queued_job.terminal?).to be(false)
    end
  end
end
