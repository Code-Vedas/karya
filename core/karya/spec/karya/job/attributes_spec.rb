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
        created_at: created_at,
        updated_at: updated_at,
        next_retry_at: next_retry_at
      )

      result = attributes.to_h

      expect(result[:id]).to eq('job123')
      expect(result[:queue]).to eq('billing')
      expect(result[:handler]).to eq('BillingSync')
      expect(result[:arguments]).to eq('account_id' => 42)
      expect(result[:state]).to eq(:queued)
      expect(result[:attempt]).to eq(1)
      expect(result[:retry_policy]).to eq(retry_policy)
      expect(result[:created_at]).to eq(created_at)
      expect(result[:updated_at]).to eq(updated_at)
      expect(result[:next_retry_at]).to eq(next_retry_at)
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
      expect(result[:next_retry_at]).to be_nil
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
          retry_policy: Object.new
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

  describe 'IdentifierNormalizer' do
    let(:identifier_normalizer_class) { Karya::Job.const_get(:Attributes, false).const_get(:IdentifierNormalizer, false) }

    describe '#normalize' do
      it 'converts to string and strips whitespace' do
        normalizer = identifier_normalizer_class.new(:id, '  job123  ')
        expect(normalizer.normalize).to eq('job123')
      end

      it 'converts symbol to string' do
        normalizer = identifier_normalizer_class.new(:queue, :billing)
        expect(normalizer.normalize).to eq('billing')
      end

      it 'freezes the result' do
        normalizer = identifier_normalizer_class.new(:handler, 'BillingSync')
        expect(normalizer.normalize).to be_frozen
      end

      it 'raises InvalidJobAttributeError for blank value' do
        expect do
          identifier_normalizer_class.new(:id, '   ').normalize
        end.to raise_error(Karya::InvalidJobAttributeError, 'id must be present')
      end

      it 'raises InvalidJobAttributeError for empty string' do
        expect do
          identifier_normalizer_class.new(:queue, '').normalize
        end.to raise_error(Karya::InvalidJobAttributeError, 'queue must be present')
      end
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
end
