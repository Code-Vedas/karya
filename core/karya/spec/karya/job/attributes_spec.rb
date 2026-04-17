# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::Job::Attributes' do
  let(:attributes_class) { Karya::Job.const_get(:Attributes, false) }
  let(:created_at) { Time.utc(2026, 3, 26, 12, 0, 0) }
  let(:updated_at) { Time.utc(2026, 3, 26, 12, 5, 0) }
  let(:retry_policy) { Karya::RetryPolicy.new(max_attempts: 3, base_delay: 5, multiplier: 2) }
  let(:next_retry_at) { Time.utc(2026, 3, 26, 12, 10, 0) }
  let(:expires_at) { Time.utc(2026, 3, 26, 12, 20, 0) }

  describe '#to_h' do
    it 'normalizes all job attributes into canonical hash' do
      attributes = attributes_class.new(
        id: 'job123',
        queue: 'billing',
        handler: 'BillingSync',
        arguments: { 'account_id' => 42 },
        state: 'queued',
        attempt: 1,
        retry_policy: retry_policy,
        execution_timeout: 15,
        expires_at: expires_at,
        idempotency_key: 'submit-123',
        uniqueness_key: 'billing:account-42',
        uniqueness_scope: :active,
        created_at: created_at,
        updated_at: updated_at,
        next_retry_at: next_retry_at,
        failure_classification: :timeout
      )

      result = attributes.to_h

      expect(result[:id]).to eq('job123')
      expect(result[:queue]).to eq('billing')
      expect(result[:handler]).to eq('BillingSync')
      expect(result[:arguments]).to eq('account_id' => 42)
      expect(result[:state]).to eq(:queued)
      expect(result[:attempt]).to eq(1)
      expect(result[:retry_policy]).to eq(retry_policy)
      expect(result[:execution_timeout]).to eq(15)
      expect(result[:expires_at]).to eq(expires_at)
      expect(result[:idempotency_key]).to eq('submit-123')
      expect(result[:uniqueness_key]).to eq('billing:account-42')
      expect(result[:uniqueness_scope]).to eq(:active)
      expect(result[:created_at]).to eq(created_at)
      expect(result[:updated_at]).to eq(updated_at)
      expect(result[:next_retry_at]).to eq(next_retry_at)
      expect(result[:failure_classification]).to eq(:timeout)
    end

    it 'defaults attempt to 0 when not provided' do
      attributes = attributes_class.new(
        id: 'job123',
        queue: 'billing',
        handler: 'BillingSync',
        state: 'queued',
        created_at: created_at
      )

      result = attributes.to_h

      expect(result[:attempt]).to eq(0)
    end

    it 'defaults priority to 0 and policy keys to nil' do
      attributes = attributes_class.new(
        id: 'job123',
        queue: 'billing',
        handler: 'BillingSync',
        state: 'queued',
        created_at: created_at
      )

      result = attributes.to_h

      expect(result[:priority]).to eq(0)
      expect(result[:concurrency_key]).to be_nil
      expect(result[:rate_limit_key]).to be_nil
      expect(result[:retry_policy]).to be_nil
      expect(result[:execution_timeout]).to be_nil
      expect(result[:expires_at]).to be_nil
      expect(result[:idempotency_key]).to be_nil
      expect(result[:uniqueness_key]).to be_nil
      expect(result[:uniqueness_scope]).to be_nil
      expect(result[:next_retry_at]).to be_nil
      expect(result[:failure_classification]).to be_nil
    end

    it 'defaults updated_at to created_at when not provided' do
      attributes = attributes_class.new(
        id: 'job123',
        queue: 'billing',
        handler: 'BillingSync',
        state: 'queued',
        created_at: created_at
      )

      result = attributes.to_h

      expect(result[:updated_at]).to eq(created_at)
    end

    it 'raises InvalidJobAttributeError when required field is missing' do
      expect do
        attributes_class.new(
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'id must be present')
    end

    it 'raises InvalidJobAttributeError for non-integer attempt' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          attempt: '1'
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'attempt must be a non-negative Integer')
    end

    it 'raises InvalidJobAttributeError for non-integer priority' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          priority: 'high'
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'priority must be an Integer')
    end

    it 'raises InvalidJobAttributeError for blank concurrency_key' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          concurrency_key: ' '
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'concurrency_key must be present')
    end

    it 'raises InvalidJobAttributeError for blank rate_limit_key' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          rate_limit_key: ''
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'rate_limit_key must be present')
    end

    it 'raises InvalidJobAttributeError for invalid retry_policy' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          retry_policy: 'not-a-policy'
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'retry_policy must be a Karya::RetryPolicy')
    end

    it 'raises InvalidJobAttributeError for blank idempotency_key' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          idempotency_key: ' '
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'idempotency_key must be present')
    end

    it 'raises InvalidJobAttributeError for blank uniqueness_key' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          uniqueness_key: ''
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'uniqueness_key must be present')
    end

    it 'raises InvalidJobAttributeError for invalid uniqueness_scope' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :forever
        ).to_h
      end.to raise_error(
        Karya::InvalidJobAttributeError,
        'uniqueness_scope must be one of :queued, :active, or :until_terminal'
      )
    end

    it 'raises InvalidJobAttributeError for non-string non-symbol uniqueness_scope' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: 123
        ).to_h
      end.to raise_error(
        Karya::InvalidJobAttributeError,
        'uniqueness_scope must be one of :queued, :active, or :until_terminal'
      )
    end

    it 'raises InvalidJobAttributeError for false uniqueness_scope' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: false
        ).to_h
      end.to raise_error(
        Karya::InvalidJobAttributeError,
        'uniqueness_scope must be one of :queued, :active, or :until_terminal'
      )
    end

    it 'raises InvalidJobAttributeError when uniqueness_scope is set without uniqueness_key' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          uniqueness_scope: :queued
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'uniqueness_scope requires uniqueness_key')
    end

    it 'normalizes false uniqueness_key when uniqueness_scope is set' do
      result = attributes_class.new(
        id: 'job123',
        queue: 'billing',
        handler: 'BillingSync',
        state: 'queued',
        created_at: created_at,
        uniqueness_key: false,
        uniqueness_scope: :queued
      ).to_h

      expect(result[:uniqueness_key]).to eq('false')
      expect(result[:uniqueness_scope]).to eq(:queued)
    end

    it 'normalizes string uniqueness_scope input' do
      result = attributes_class.new(
        id: 'job123',
        queue: 'billing',
        handler: 'BillingSync',
        state: 'queued',
        created_at: created_at,
        uniqueness_key: 'billing:account-42',
        uniqueness_scope: 'until_terminal'
      ).to_h

      expect(result[:uniqueness_scope]).to eq(:until_terminal)
    end

    it 'rejects whitespace-padded uniqueness_scope input' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: ' queued '
        ).to_h
      end.to raise_error(
        Karya::InvalidJobAttributeError,
        'uniqueness_scope must be one of :queued, :active, or :until_terminal'
      )
    end

    it 'raises InvalidJobAttributeError for false retry_policy' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          retry_policy: false
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'retry_policy must be a Karya::RetryPolicy')
    end

    it 'raises InvalidJobAttributeError for invalid next_retry_at' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          next_retry_at: 'later'
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'next_retry_at must be a Time')
    end

    it 'raises InvalidJobAttributeError for invalid execution_timeout' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          execution_timeout: 0
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'execution_timeout must be a positive finite number')
    end

    it 'raises InvalidJobAttributeError for invalid expires_at' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          expires_at: 'later'
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'expires_at must be a Time')
    end

    it 'raises InvalidJobAttributeError for invalid failure_classification' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          failure_classification: :boom
        ).to_h
      end.to raise_error(
        Karya::InvalidJobAttributeError,
        'failure_classification must be one of :error, :timeout, or :expired'
      )
    end

    it 'raises InvalidJobAttributeError for non-string non-symbol failure_classification' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          failure_classification: 123
        ).to_h
      end.to raise_error(
        Karya::InvalidJobAttributeError,
        'failure_classification must be one of :error, :timeout, or :expired'
      )
    end

    it 'raises InvalidJobAttributeError for arbitrary string failure_classification' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          failure_classification: 'arbitrary'
        ).to_h
      end.to raise_error(
        Karya::InvalidJobAttributeError,
        'failure_classification must be one of :error, :timeout, or :expired'
      )
    end

    it 'raises InvalidJobAttributeError for negative attempt' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          attempt: -1
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'attempt must be a non-negative Integer')
    end

    it 'raises InvalidJobAttributeError for invalid lifecycle collaborators' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          lifecycle: Object.new
        ).to_h
      end.to raise_error(
        Karya::InvalidJobAttributeError,
        /lifecycle must respond to #normalize_state, #validate_state!, #valid_transition\?, #validate_transition!, #terminal\?/
      )
    end
  end

  describe 'TimestampNormalizer' do
    let(:timestamp_normalizer_class) { Karya::Job.const_get(:Attributes, false).const_get(:TimestampNormalizer, false) }

    describe '#normalize' do
      it 'duplicates and freezes Time object' do
        time = Time.utc(2026, 3, 26, 12, 0, 0)
        normalizer = timestamp_normalizer_class.new(:created_at, time)
        result = normalizer.normalize

        expect(result).to eq(time)
        expect(result).to be_frozen
        expect(result.object_id).not_to eq(time.object_id)
      end

      it 'raises InvalidJobAttributeError for non-Time value' do
        expect do
          timestamp_normalizer_class.new(:created_at, '2026-03-26').normalize
        end.to raise_error(Karya::InvalidJobAttributeError, 'created_at must be a Time')
      end

      it 'raises InvalidJobAttributeError for integer timestamp' do
        expect do
          timestamp_normalizer_class.new(:updated_at, 1_234_567_890).normalize
        end.to raise_error(Karya::InvalidJobAttributeError, 'updated_at must be a Time')
      end
    end
  end

  describe 'expiration copy' do
    it 'builds a failed expired copy without changing durable identity and scheduling fields' do
      job = Karya::Job.new(
        id: 'job123',
        queue: 'billing',
        handler: 'BillingSync',
        arguments: { 'account_id' => 42 },
        state: 'retry_pending',
        attempt: 2,
        priority: 10,
        retry_policy: retry_policy,
        execution_timeout: 15,
        expires_at: expires_at,
        created_at: created_at,
        updated_at: updated_at,
        next_retry_at: next_retry_at,
        failure_classification: :timeout
      )

      expired_job = job.expire(updated_at: updated_at + 60)

      expect(expired_job.id).to eq('job123')
      expect(expired_job.queue).to eq('billing')
      expect(expired_job.handler).to eq('BillingSync')
      expect(expired_job.arguments).to eq('account_id' => 42)
      expect(expired_job.priority).to eq(10)
      expect(expired_job.retry_policy).to eq(retry_policy)
      expect(expired_job.execution_timeout).to eq(15)
      expect(expired_job.expires_at).to eq(expires_at)
      expect(expired_job.state).to eq(:failed)
      expect(expired_job.attempt).to eq(2)
      expect(expired_job.created_at).to eq(created_at)
      expect(expired_job.updated_at).to eq(updated_at + 60)
      expect(expired_job.next_retry_at).to be_nil
      expect(expired_job.failure_classification).to eq(:expired)
    end
  end
end
