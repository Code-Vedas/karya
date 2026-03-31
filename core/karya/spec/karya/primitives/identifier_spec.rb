# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Primitives::Identifier do
  subject(:identifier) { described_class.new(name, value, error_class:) }

  let(:name) { :queue }
  let(:error_class) { ArgumentError }

  describe '#normalize' do
    context 'with valid identifiers' do
      it 'returns a simple string' do
        result = described_class.new(name, 'billing', error_class:).normalize
        expect(result).to eq('billing')
      end

      it 'returns a symbol converted to string' do
        result = described_class.new(name, :billing, error_class:).normalize
        expect(result).to eq('billing')
      end

      it 'strips leading whitespace' do
        result = described_class.new(name, '  billing', error_class:).normalize
        expect(result).to eq('billing')
      end

      it 'strips trailing whitespace' do
        result = described_class.new(name, 'billing  ', error_class:).normalize
        expect(result).to eq('billing')
      end

      it 'strips leading and trailing whitespace' do
        result = described_class.new(name, '  billing  ', error_class:).normalize
        expect(result).to eq('billing')
      end

      it 'converts integer to string' do
        result = described_class.new(name, 123, error_class:).normalize
        expect(result).to eq('123')
      end

      it 'handles hyphenated identifiers' do
        result = described_class.new(name, 'user-sync', error_class:).normalize
        expect(result).to eq('user-sync')
      end

      it 'handles underscored identifiers' do
        result = described_class.new(name, 'user_sync', error_class:).normalize
        expect(result).to eq('user_sync')
      end

      it 'preserves internal whitespace' do
        result = described_class.new(name, 'user sync', error_class:).normalize
        expect(result).to eq('user sync')
      end
    end

    context 'with invalid identifiers' do
      it 'raises error for empty string' do
        expect do
          described_class.new(name, '', error_class:).normalize
        end.to raise_error(ArgumentError, 'queue must be present')
      end

      it 'raises error for blank string (only spaces)' do
        expect do
          described_class.new(name, '   ', error_class:).normalize
        end.to raise_error(ArgumentError, 'queue must be present')
      end

      it 'raises error for blank string (tabs and spaces)' do
        expect do
          described_class.new(name, " \t ", error_class:).normalize
        end.to raise_error(ArgumentError, 'queue must be present')
      end

      it 'raises error for nil' do
        expect do
          described_class.new(name, nil, error_class:).normalize
        end.to raise_error(ArgumentError, 'queue must be present')
      end
    end

    context 'with custom error class' do
      let(:error_class) { StandardError }

      it 'raises the custom error class' do
        expect do
          described_class.new(name, '', error_class:).normalize
        end.to raise_error(StandardError, 'queue must be present')
      end
    end

    context 'with custom name' do
      let(:name) { :worker_id }

      it 'includes the custom name in error message' do
        expect do
          described_class.new(name, '', error_class:).normalize
        end.to raise_error(ArgumentError, 'worker_id must be present')
      end
    end
  end
end
