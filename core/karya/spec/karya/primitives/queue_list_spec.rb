# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Primitives::QueueList do
  subject(:queue_list) { described_class.new(values, error_class:) }

  let(:error_class) { ArgumentError }

  describe '#normalize' do
    context 'with valid queue lists' do
      it 'returns array with single queue name' do
        result = described_class.new(['billing'], error_class:).normalize
        expect(result).to eq(['billing'])
        expect(result).to be_frozen
      end

      it 'returns array with multiple queue names' do
        result = described_class.new(%w[billing email reports], error_class:).normalize
        expect(result).to eq(%w[billing email reports])
        expect(result).to be_frozen
      end

      it 'normalizes symbols to strings' do
        result = described_class.new(%i[billing email], error_class:).normalize
        expect(result).to eq(%w[billing email])
        expect(result).to be_frozen
      end

      it 'normalizes mixed symbols and strings' do
        result = described_class.new([:billing, 'email'], error_class:).normalize
        expect(result).to eq(%w[billing email])
        expect(result).to be_frozen
      end

      it 'strips whitespace from queue names' do
        result = described_class.new(['  billing  ', 'email'], error_class:).normalize
        expect(result).to eq(%w[billing email])
        expect(result).to be_frozen
      end

      it 'handles single queue name as string' do
        result = described_class.new('billing', error_class:).normalize
        expect(result).to eq(['billing'])
        expect(result).to be_frozen
      end

      it 'handles single queue name as symbol' do
        result = described_class.new(:billing, error_class:).normalize
        expect(result).to eq(['billing'])
        expect(result).to be_frozen
      end

      it 'converts integers to strings' do
        result = described_class.new([1, 2, 3], error_class:).normalize
        expect(result).to eq(%w[1 2 3])
        expect(result).to be_frozen
      end

      it 'handles hyphenated queue names' do
        result = described_class.new(%w[user-sync data-import], error_class:).normalize
        expect(result).to eq(%w[user-sync data-import])
        expect(result).to be_frozen
      end

      it 'handles underscored queue names' do
        result = described_class.new(%w[user_sync data_import], error_class:).normalize
        expect(result).to eq(%w[user_sync data_import])
        expect(result).to be_frozen
      end
    end

    context 'with invalid queue lists' do
      it 'raises error for empty array' do
        expect do
          described_class.new([], error_class:).normalize
        end.to raise_error(ArgumentError, 'queues must be present')
      end

      it 'raises error for nil' do
        expect do
          described_class.new(nil, error_class:).normalize
        end.to raise_error(ArgumentError, 'queues must be present')
      end

      it 'raises error for array with empty string' do
        expect do
          described_class.new([''], error_class:).normalize
        end.to raise_error(ArgumentError, 'queue must be present')
      end

      it 'raises error for array with blank string' do
        expect do
          described_class.new(['   '], error_class:).normalize
        end.to raise_error(ArgumentError, 'queue must be present')
      end

      it 'raises error when one queue name is blank' do
        expect do
          described_class.new(['billing', '', 'email'], error_class:).normalize
        end.to raise_error(ArgumentError, 'queue must be present')
      end

      it 'raises error when one queue name is whitespace only' do
        expect do
          described_class.new(['billing', '   ', 'email'], error_class:).normalize
        end.to raise_error(ArgumentError, 'queue must be present')
      end

      it 'raises error for array containing nil' do
        expect do
          described_class.new(['billing', nil], error_class:).normalize
        end.to raise_error(ArgumentError, 'queue must be present')
      end
    end

    context 'with custom error class' do
      let(:error_class) { StandardError }

      it 'raises the custom error class for empty list' do
        expect do
          described_class.new([], error_class:).normalize
        end.to raise_error(StandardError, 'queues must be present')
      end

      it 'raises the custom error class for invalid queue name' do
        expect do
          described_class.new([''], error_class:).normalize
        end.to raise_error(StandardError, 'queue must be present')
      end
    end

    describe 'immutability' do
      it 'returns a frozen array' do
        result = described_class.new(['billing'], error_class:).normalize
        expect(result).to be_frozen
      end

      it 'prevents modification of returned array' do
        result = described_class.new(['billing'], error_class:).normalize
        expect { result << 'email' }.to raise_error(FrozenError)
      end
    end
  end
end
