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
  let(:expires_at) { Time.utc(2026, 3, 26, 12, 20, 0) }

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
        execution_timeout: 15,
        expires_at: expires_at,
        idempotency_key: 'submit-123',
        uniqueness_key: 'billing:account-42',
        uniqueness_scope: :active,
        state: 'retry-pending',
        attempt: 2,
        created_at:,
        updated_at:,
        next_retry_at: next_retry_at,
        failure_classification: :timeout
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
      expect(job.concurrency_scope).to eq(Karya::Backpressure::Scope.new(kind: :custom, value: 'account-42'))
      expect(job.rate_limit_scope).to eq(Karya::Backpressure::Scope.new(kind: :custom, value: 'partner-api'))
      expect(job.concurrency_key).to eq('custom:account-42')
      expect(job.rate_limit_key).to eq('custom:partner-api')
      expect(job.retry_policy).to eq(retry_policy)
      expect(job.execution_timeout).to eq(15)
      expect(job.expires_at).to eq(expires_at)
      expect(job.idempotency_key).to eq('submit-123')
      expect(job.uniqueness_key).to eq('billing:account-42')
      expect(job.uniqueness_scope).to eq(:active)
      expect(job.state).to eq(:retry_pending)
      expect(job.attempt).to eq(2)
      expect(job.created_at).to eq(created_at)
      expect(job.updated_at).to eq(updated_at)
      expect(job.next_retry_at).to eq(next_retry_at)
      expect(job.failure_classification).to eq(:timeout)
      expect([job.created_at, job.updated_at, job.next_retry_at]).to all(be_frozen)
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

    it 'returns nil compatibility keys when no explicit backpressure scopes exist' do
      job = described_class.new(
        id: 'job123',
        queue: 'billing',
        handler: 'billing_sync',
        state: :queued,
        created_at:
      )

      expect(job.concurrency_scope).to be_nil
      expect(job.rate_limit_scope).to be_nil
      expect(job.concurrency_key).to be_nil
      expect(job.rate_limit_key).to be_nil
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

    it 'preserves timing and policy keys across transitions' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        priority: 9,
        concurrency_key: 'account-9',
        rate_limit_key: 'partner-api',
        retry_policy: retry_policy,
        execution_timeout: 12,
        expires_at: expires_at,
        idempotency_key: 'submit-123',
        uniqueness_key: 'billing:account-9',
        uniqueness_scope: :until_terminal,
        state: :reserved,
        created_at:,
        next_retry_at: next_retry_at
      )

      transitioned_job = job.transition_to(:running, updated_at:)

      expect(transitioned_job.priority).to eq(9)
      expect(transitioned_job.concurrency_scope).to eq(Karya::Backpressure::Scope.new(kind: :custom, value: 'account-9'))
      expect(transitioned_job.rate_limit_scope).to eq(Karya::Backpressure::Scope.new(kind: :custom, value: 'partner-api'))
      expect(transitioned_job.concurrency_key).to eq('custom:account-9')
      expect(transitioned_job.rate_limit_key).to eq('custom:partner-api')
      expect(transitioned_job.retry_policy).to eq(retry_policy)
      expect(transitioned_job.execution_timeout).to eq(12)
      expect(transitioned_job.expires_at).to eq(expires_at)
      expect(transitioned_job.idempotency_key).to eq('submit-123')
      expect(transitioned_job.uniqueness_key).to eq('billing:account-9')
      expect(transitioned_job.uniqueness_scope).to eq(:until_terminal)
      expect(transitioned_job.next_retry_at).to eq(next_retry_at)
    end

    it 'preserves uniqueness metadata when expiring a job' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        idempotency_key: 'submit-123',
        uniqueness_key: 'billing:account-9',
        uniqueness_scope: :queued,
        state: :queued,
        created_at:
      )

      expired_job = job.expire(updated_at: updated_at)

      expect(expired_job.idempotency_key).to eq('submit-123')
      expect(expired_job.uniqueness_key).to eq('billing:account-9')
      expect(expired_job.uniqueness_scope).to eq(:queued)
    end

    it 'allows overriding retry metadata and failure classification during transition' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        retry_policy: retry_policy,
        state: :failed,
        attempt: 1,
        created_at:,
        failure_classification: :error
      )

      transitioned_job = job.transition_to(
        :retry_pending,
        updated_at:,
        next_retry_at: next_retry_at,
        retry_policy: retry_policy,
        failure_classification: :timeout
      )

      expect(transitioned_job.retry_policy).to eq(retry_policy)
      expect(transitioned_job.next_retry_at).to eq(next_retry_at)
      expect(transitioned_job.failure_classification).to eq(:timeout)
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

    it 'preserves explicit backpressure scopes across transitions' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        concurrency_scope: { kind: :tenant, value: 'tenant-9' },
        rate_limit_scope: { kind: :workflow, value: 'nightly-billing' },
        state: :reserved,
        created_at:
      )

      transitioned_job = job.transition_to(:running, updated_at:)

      expect(transitioned_job.concurrency_scope).to eq(Karya::Backpressure::Scope.new(kind: :tenant, value: 'tenant-9'))
      expect(transitioned_job.rate_limit_scope).to eq(Karya::Backpressure::Scope.new(kind: :workflow, value: 'nightly-billing'))
      expect(transitioned_job.concurrency_key).to eq('tenant:tenant-9')
      expect(transitioned_job.rate_limit_key).to eq('workflow:nightly-billing')
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

  describe 'failure classification validation' do
    it 'rejects non-string non-symbol values' do
      expect do
        described_class.new(
          id: 'job_123',
          queue: 'billing',
          handler: 'billing_sync',
          state: :failed,
          created_at:,
          failure_classification: 123
        )
      end.to raise_error(
        Karya::InvalidJobAttributeError,
        'failure_classification must be one of :error, :timeout, or :expired'
      )
    end

    it 'rejects arbitrary strings without symbolizing them' do
      expect do
        described_class.new(
          id: 'job_123',
          queue: 'billing',
          handler: 'billing_sync',
          state: :failed,
          created_at:,
          failure_classification: 'arbitrary_string'
        )
      end.to raise_error(
        Karya::InvalidJobAttributeError,
        'failure_classification must be one of :error, :timeout, or :expired'
      )
    end
  end
end
