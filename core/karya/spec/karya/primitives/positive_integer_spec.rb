# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Primitives::PositiveInteger do
  subject(:positive_integer) { described_class.new(name, value, error_class:) }

  let(:name) { :threads }
  let(:error_class) { ArgumentError }

  describe '#normalize' do
    context 'with valid positive integers' do
      it 'returns one' do
        result = described_class.new(name, 1, error_class:).normalize
        expect(result).to eq(1)
      end

      it 'returns small positive integer' do
        result = described_class.new(name, 5, error_class:).normalize
        expect(result).to eq(5)
      end

      it 'returns large positive integer' do
        result = described_class.new(name, 1000, error_class:).normalize
        expect(result).to eq(1000)
      end

      it 'returns very large positive integer' do
        result = described_class.new(name, 1_000_000, error_class:).normalize
        expect(result).to eq(1_000_000)
      end
    end

    context 'with invalid positive integers' do
      it 'raises error for zero' do
        expect do
          described_class.new(name, 0, error_class:).normalize
        end.to raise_error(ArgumentError, 'threads must be a positive Integer')
      end

      it 'raises error for negative integer' do
        expect do
          described_class.new(name, -1, error_class:).normalize
        end.to raise_error(ArgumentError, 'threads must be a positive Integer')
      end

      it 'raises error for positive float' do
        expect do
          described_class.new(name, 1.5, error_class:).normalize
        end.to raise_error(ArgumentError, 'threads must be a positive Integer')
      end

      it 'raises error for positive BigDecimal' do
        expect do
          described_class.new(name, BigDecimal('1'), error_class:).normalize
        end.to raise_error(ArgumentError, 'threads must be a positive Integer')
      end

      it 'raises error for nil' do
        expect do
          described_class.new(name, nil, error_class:).normalize
        end.to raise_error(ArgumentError, 'threads must be a positive Integer')
      end

      it 'raises error for string' do
        expect do
          described_class.new(name, '5', error_class:).normalize
        end.to raise_error(ArgumentError, 'threads must be a positive Integer')
      end

      it 'raises error for array' do
        expect do
          described_class.new(name, [5], error_class:).normalize
        end.to raise_error(ArgumentError, 'threads must be a positive Integer')
      end

      it 'raises error for hash' do
        expect do
          described_class.new(name, { value: 5 }, error_class:).normalize
        end.to raise_error(ArgumentError, 'threads must be a positive Integer')
      end

      it 'raises error for true' do
        expect do
          described_class.new(name, true, error_class:).normalize
        end.to raise_error(ArgumentError, 'threads must be a positive Integer')
      end

      it 'raises error for false' do
        expect do
          described_class.new(name, false, error_class:).normalize
        end.to raise_error(ArgumentError, 'threads must be a positive Integer')
      end
    end

    context 'with custom error class' do
      let(:error_class) { StandardError }

      it 'raises the custom error class' do
        expect do
          described_class.new(name, 0, error_class:).normalize
        end.to raise_error(StandardError, 'threads must be a positive Integer')
      end
    end

    context 'with custom name' do
      let(:name) { :processes }

      it 'includes the custom name in error message' do
        expect do
          described_class.new(name, 0, error_class:).normalize
        end.to raise_error(ArgumentError, 'processes must be a positive Integer')
      end
    end
  end
end
