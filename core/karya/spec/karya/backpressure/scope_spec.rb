# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Backpressure::Scope do
  let(:tagged_string_class) { Class.new(String) }

  describe '.from' do
    it 'rejects missing scope input' do
      expect do
        described_class.from(nil)
      end.to raise_error(Karya::Backpressure::InvalidPolicyError, 'scope must be present')
    end

    it 'builds custom scopes from string-like shorthand' do
      scope = described_class.from(tagged_string_class.new('tenant-7'))

      expect(scope.kind).to eq(:custom)
      expect(scope.value).to eq('tenant-7')
      expect(scope.key).to eq('custom:tenant-7')
      expect(scope.to_h).to eq(kind: :custom, value: 'tenant-7')
    end

    it 'rejects unsupported scope input types' do
      expect do
        described_class.from(123)
      end.to raise_error(
        Karya::Backpressure::InvalidPolicyError,
        'scope must be a Karya::Backpressure::Scope, Hash, String, or Symbol'
      )
    end

    it 'rejects unsupported scope kinds' do
      expect do
        described_class.new(kind: :region, value: 'ca-central-1')
      end.to raise_error(
        Karya::Backpressure::InvalidPolicyError,
        'scope kind must be one of :queue, :handler, :tenant, :workflow, or :custom'
      )
    end

    it 'rejects non-string non-symbol scope values' do
      expect do
        described_class.new(kind: :tenant, value: 123)
      end.to raise_error(
        Karya::Backpressure::InvalidPolicyError,
        'value must be a String or Symbol'
      )
    end

    it 'keeps InvalidPolicyError when scope support uses the default error class' do
      expect do
        Karya::Backpressure::ScopeSupport.normalize_scope(:scope, ' ')
      end.to raise_error(Karya::Backpressure::InvalidPolicyError, 'scope must be present')
    end

    it 're-raises unexpected standard errors from scope normalization' do
      allow(described_class).to receive(:from).and_raise(RuntimeError, 'boom')

      expect do
        Karya::Backpressure::ScopeSupport.normalize_scope(:scope, 'tenant-7')
      end.to raise_error(RuntimeError, 'boom')
    end
  end

  describe '#==' do
    it 'compares scopes by normalized key and exposes a stable hash' do
      left = described_class.new(kind: :tenant, value: 'tenant-7')
      right = described_class.new(kind: 'tenant', value: 'tenant-7')

      expect(left).to eq(right)
      expect(left.hash).to eq(right.hash)
      expect(left.eql?(right)).to be(true)
      expect(left == 'tenant-7').to be(false)
    end
  end

  describe 'internal identifier normalization' do
    it 'normalizes identifier-like input through the shared normalizer' do
      normalizers = Karya::Backpressure.const_get(:Normalizers, false)

      expect(normalizers.identifier(:key, ' account_sync ')).to eq('account_sync')
    end
  end

  describe 'legacy policy key shorthands' do
    it 'supports key-only policy constructors and rejects conflicting key and scope input' do
      concurrency_policy = Karya::Backpressure::ConcurrencyPolicy.new(key: 'account_sync', limit: 2)
      rate_limit_policy = Karya::Backpressure::RateLimitPolicy.new(key: 'partner_api', limit: 5, period: 60)

      expect(concurrency_policy.key).to eq('custom:account_sync')
      expect(rate_limit_policy.key).to eq('custom:partner_api')

      expect do
        Karya::Backpressure::ConcurrencyPolicy.new(key: 'account_sync', scope: { kind: :custom, value: 'account_sync' }, limit: 1)
      end.to raise_error(Karya::Backpressure::InvalidPolicyError, 'provide only one of scope or key')

      expect do
        Karya::Backpressure::RateLimitPolicy.new(
          key: 'partner_api',
          scope: { kind: :custom, value: 'partner_api' },
          limit: 1,
          period: 60
        )
      end.to raise_error(Karya::Backpressure::InvalidPolicyError, 'provide only one of scope or key')
    end
  end
end
