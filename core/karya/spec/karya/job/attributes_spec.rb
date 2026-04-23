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
  let(:retry_policies) do
    Karya::RetryPolicySet.new(
      policies: {
        fast: { max_attempts: 2, base_delay: 1, multiplier: 2, jitter_strategy: :equal }
      }
    )
  end
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
        failure_classification: :timeout,
        dead_letter_reason: 'retry-policy-exhausted',
        dead_lettered_at: updated_at,
        dead_letter_source_state: :failed
      )

      result = attributes.to_h

      expect(result[:id]).to eq('job123')
      expect(result[:queue]).to eq('billing')
      expect(result[:handler]).to eq('BillingSync')
      expect(result[:arguments]).to eq('account_id' => 42)
      expect(result[:state]).to eq(:queued)
      expect(result[:attempt]).to eq(1)
      expect(result[:concurrency_scope]).to be_nil
      expect(result[:rate_limit_scope]).to be_nil
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
      expect(result[:dead_letter_reason]).to eq('retry-policy-exhausted')
      expect(result[:dead_lettered_at]).to eq(updated_at)
      expect(result[:dead_letter_source_state]).to eq(:failed)
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
      expect(result[:concurrency_scope]).to be_nil
      expect(result[:rate_limit_scope]).to be_nil
      expect(result[:retry_policy]).to be_nil
      expect(result[:execution_timeout]).to be_nil
      expect(result[:expires_at]).to be_nil
      expect(result[:idempotency_key]).to be_nil
      expect(result[:uniqueness_key]).to be_nil
      expect(result[:uniqueness_scope]).to be_nil
      expect(result[:next_retry_at]).to be_nil
      expect(result[:failure_classification]).to be_nil
      expect(result[:dead_letter_reason]).to be_nil
      expect(result[:dead_lettered_at]).to be_nil
      expect(result[:dead_letter_source_state]).to be_nil
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
      end.to raise_error(Karya::InvalidJobAttributeError, 'retry_policy references require retry_policies')
    end

    it 'normalizes explicit backpressure scopes' do
      attributes = attributes_class.new(
        id: 'job123',
        queue: 'billing',
        handler: 'BillingSync',
        state: 'queued',
        created_at: created_at,
        concurrency_scope: { kind: :tenant, value: 'tenant-42' },
        rate_limit_scope: { 'kind' => 'workflow', 'value' => 'nightly-billing' }
      )

      result = attributes.to_h

      expect(result[:concurrency_scope]).to eq(Karya::Backpressure::Scope.new(kind: :tenant, value: 'tenant-42'))
      expect(result[:rate_limit_scope]).to eq(Karya::Backpressure::Scope.new(kind: :workflow, value: 'nightly-billing'))
    end

    it 'raises InvalidJobAttributeError when both scope and legacy key are given' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          concurrency_scope: { kind: :tenant, value: 'tenant-42' },
          concurrency_key: 'legacy'
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'provide only one of concurrency_scope or concurrency_key')
    end

    it 'raises InvalidJobAttributeError when queue scope does not match job queue' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          concurrency_scope: { kind: :queue, value: 'email' }
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'concurrency_scope queue scope must match job queue')
    end

    it 'raises InvalidJobAttributeError when handler scope does not match job handler' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          rate_limit_scope: { kind: :handler, value: 'OtherHandler' }
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'rate_limit_scope handler scope must match job handler')
    end

    it 'accepts queue and handler scopes when they match routing metadata' do
      attributes = attributes_class.new(
        id: 'job123',
        queue: 'billing',
        handler: 'BillingSync',
        state: 'queued',
        created_at: created_at,
        concurrency_scope: { kind: :queue, value: 'billing' },
        rate_limit_scope: { kind: :handler, value: 'BillingSync' }
      )

      result = attributes.to_h

      expect(result[:concurrency_scope]).to eq(Karya::Backpressure::Scope.new(kind: :queue, value: 'billing'))
      expect(result[:rate_limit_scope]).to eq(Karya::Backpressure::Scope.new(kind: :handler, value: 'BillingSync'))
    end

    it 'treats legacy backpressure keys as custom shorthands even with reserved prefixes' do
      attributes = attributes_class.new(
        id: 'job123',
        queue: 'billing',
        handler: 'BillingSync',
        state: 'queued',
        created_at: created_at,
        concurrency_key: 'queue:other',
        rate_limit_key: 'handler:OtherHandler'
      )

      result = attributes.to_h

      expect(result[:concurrency_scope]).to eq(Karya::Backpressure::Scope.new(kind: :custom, value: 'queue:other'))
      expect(result[:rate_limit_scope]).to eq(Karya::Backpressure::Scope.new(kind: :custom, value: 'handler:OtherHandler'))
    end

    it 'resolves named retry policies through retry_policies' do
      attributes = attributes_class.new(
        id: 'job123',
        queue: 'billing',
        handler: 'BillingSync',
        state: 'queued',
        created_at: created_at,
        retry_policy: :fast,
        retry_policies: retry_policies
      )

      result = attributes.to_h

      expect(result[:retry_policy]).to eq(retry_policies.policy_for(:fast))
    end

    it 'raises InvalidJobAttributeError for unknown named retry policies' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          retry_policy: :missing,
          retry_policies: retry_policies
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'unknown retry policy :missing')
    end

    it 'maps invalid named retry policy references through job attribute errors' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          retry_policy: ' ',
          retry_policies: retry_policies
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'retry_policy must be present')
    end

    it 'raises InvalidJobAttributeError for invalid retry_policies input' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'queued',
          created_at: created_at,
          retry_policy: :fast,
          retry_policies: []
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'retry_policies must be a Hash or Karya::RetryPolicySet')
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
      end.to raise_error(Karya::InvalidJobAttributeError, 'retry_policy must be a Karya::RetryPolicy, String, or Symbol')
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

    it 'raises InvalidJobAttributeError for invalid dead_letter_reason' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'dead_letter',
          created_at: created_at,
          dead_letter_reason: :retry_exhausted
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'dead_letter_reason must be a String')
    end

    it 'raises InvalidJobAttributeError for overly long dead_letter_reason' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'dead_letter',
          created_at: created_at,
          dead_letter_reason: 'a' * 1025
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'dead_letter_reason must be at most 1024 characters')
    end

    it 'raises InvalidJobAttributeError for empty dead_letter_reason' do
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'dead_letter',
          created_at: created_at,
          dead_letter_reason: ''
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'dead_letter_reason must be present')
    end

    it 'strips dead_letter_reason and rejects whitespace-only input' do
      result = attributes_class.new(
        id: 'job123',
        queue: 'billing',
        handler: 'BillingSync',
        state: 'dead_letter',
        created_at: created_at,
        dead_letter_reason: ' retry-policy-exhausted '
      ).to_h

      expect(result[:dead_letter_reason]).to eq('retry-policy-exhausted')
      expect(result[:dead_letter_reason]).to be_frozen
      expect do
        attributes_class.new(
          id: 'job123',
          queue: 'billing',
          handler: 'BillingSync',
          state: 'dead_letter',
          created_at: created_at,
          dead_letter_reason: " \t "
        ).to_h
      end.to raise_error(Karya::InvalidJobAttributeError, 'dead_letter_reason must be present')
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
