# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Job do
  let(:created_at) { Time.utc(2026, 3, 26, 12, 0, 0) }
  let(:updated_at) { Time.utc(2026, 3, 26, 12, 5, 0) }

  describe '#initialize' do
    it 'builds an immutable canonical job with normalized fields' do
      job = described_class.new(
        id: :job123,
        queue: 'billing',
        handler: :billing_sync,
        arguments: { 'account_id' => 42, metadata: { source: 'sync' }, tags: ['vip'] },
        state: 'retry-pending',
        attempt: 2,
        created_at:,
        updated_at:
      )

      expect(job.id).to eq('job123')
      expect(job.queue).to eq('billing')
      expect(job.handler).to eq('billing_sync')
      expect(job.arguments).to eq(account_id: 42, metadata: { source: 'sync' }, tags: ['vip'])
      expect(job.arguments).to be_frozen
      expect(job.arguments[:metadata]).to be_frozen
      expect(job.arguments[:tags]).to be_frozen
      expect(job.state).to eq(:retry_pending)
      expect(job.attempt).to eq(2)
      expect(job.created_at).to eq(created_at)
      expect(job.updated_at).to eq(updated_at)
      expect(job).to be_frozen
    end

    it 'defaults updated_at to created_at' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        state: :queued,
        created_at:
      )

      expect(job.updated_at).to eq(created_at)
    end

    it 'rejects missing required fields' do
      expect do
        described_class.new(
          queue: 'billing',
          handler: 'billing_sync',
          state: :queued,
          created_at:
        )
      end.to raise_error(Karya::InvalidJobAttributeError, /id must be present/)
    end

    it 'rejects blank identifiers' do
      expect do
        described_class.new(
          id: '',
          queue: 'billing',
          handler: 'billing_sync',
          state: :queued,
          created_at:
        )
      end.to raise_error(Karya::InvalidJobAttributeError, /id must be present/)
    end

    it 'rejects non-hash arguments' do
      expect do
        described_class.new(
          id: 'job_123',
          queue: 'billing',
          handler: 'billing_sync',
          arguments: nil,
          state: :queued,
          created_at:
        )
      end.to raise_error(Karya::InvalidJobAttributeError, /arguments must be a Hash/)
    end

    it 'normalizes argument keys through string conversion' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        arguments: { 123 => 'value' },
        state: :queued,
        created_at:
      )

      expect(job.arguments).to eq('123': 'value')
    end

    it 'does not freeze caller-owned scalar argument values' do
      message = +'hello'

      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        arguments: { message: },
        state: :queued,
        created_at:
      )

      expect(job.arguments[:message]).to eq('hello')
      expect(job.arguments[:message]).to be_frozen
      expect(message).not_to be_frozen
    end

    it 'accepts non-duplicable scalar argument values' do
      job = described_class.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        arguments: { attempt_limit: 3 },
        state: :queued,
        created_at:
      )

      expect(job.arguments).to eq(attempt_limit: 3)
    end

    it 'rejects blank argument keys' do
      expect do
        described_class.new(
          id: 'job_123',
          queue: 'billing',
          handler: 'billing_sync',
          arguments: { '   ' => 'value' },
          state: :queued,
          created_at:
        )
      end.to raise_error(Karya::InvalidJobAttributeError, /argument keys must be present/)
    end

    it 'rejects invalid attempts' do
      expect do
        described_class.new(
          id: 'job_123',
          queue: 'billing',
          handler: 'billing_sync',
          state: :queued,
          attempt: -1,
          created_at:
        )
      end.to raise_error(Karya::InvalidJobAttributeError, /attempt must be a non-negative Integer/)
    end

    it 'rejects non-time timestamps' do
      expect do
        described_class.new(
          id: 'job_123',
          queue: 'billing',
          handler: 'billing_sync',
          state: :queued,
          created_at: '2026-03-26T12:00:00Z'
        )
      end.to raise_error(Karya::InvalidJobAttributeError, /created_at must be a Time/)
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
        .to raise_error(Karya::InvalidJobTransitionError, /Cannot transition/)
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
