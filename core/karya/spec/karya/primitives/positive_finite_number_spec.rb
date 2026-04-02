# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Primitives::PositiveFiniteNumber do
  subject(:number) { described_class.new(name, value, error_class:) }

  let(:name) { :lease_duration }
  let(:error_class) { ArgumentError }

  describe '#normalize' do
    context 'with valid positive finite numbers' do
      it 'returns positive integer' do
        result = described_class.new(name, 42, error_class:).normalize
        expect(result).to eq(42)
      end

      it 'returns one' do
        result = described_class.new(name, 1, error_class:).normalize
        expect(result).to eq(1)
      end

      it 'returns positive float' do
        result = described_class.new(name, 3.14, error_class:).normalize
        expect(result).to eq(3.14)
      end

      it 'returns very small positive float' do
        result = described_class.new(name, 0.001, error_class:).normalize
        expect(result).to eq(0.001)
      end

      it 'returns very large number' do
        result = described_class.new(name, 1_000_000, error_class:).normalize
        expect(result).to eq(1_000_000)
      end

      it 'returns positive BigDecimal' do
        value = BigDecimal('123.45')
        result = described_class.new(name, value, error_class:).normalize
        expect(result).to eq(value)
      end

      it 'returns minimal positive BigDecimal' do
        value = BigDecimal('0.0001')
        result = described_class.new(name, value, error_class:).normalize
        expect(result).to eq(value)
      end
    end

    context 'with invalid positive finite numbers' do
      it 'raises error for zero' do
        expect do
          described_class.new(name, 0, error_class:).normalize
        end.to raise_error(ArgumentError, 'lease_duration must be a positive finite number')
      end

      it 'raises error for zero float' do
        expect do
          described_class.new(name, 0.0, error_class:).normalize
        end.to raise_error(ArgumentError, 'lease_duration must be a positive finite number')
      end

      it 'raises error for negative integer' do
        expect do
          described_class.new(name, -1, error_class:).normalize
        end.to raise_error(ArgumentError, 'lease_duration must be a positive finite number')
      end

      it 'raises error for negative float' do
        expect do
          described_class.new(name, -0.1, error_class:).normalize
        end.to raise_error(ArgumentError, 'lease_duration must be a positive finite number')
      end

      it 'raises error for positive infinity' do
        expect do
          described_class.new(name, Float::INFINITY, error_class:).normalize
        end.to raise_error(ArgumentError, 'lease_duration must be a positive finite number')
      end

      it 'raises error for negative infinity' do
        expect do
          described_class.new(name, -Float::INFINITY, error_class:).normalize
        end.to raise_error(ArgumentError, 'lease_duration must be a positive finite number')
      end

      it 'raises error for NaN' do
        expect do
          described_class.new(name, Float::NAN, error_class:).normalize
        end.to raise_error(ArgumentError, 'lease_duration must be a positive finite number')
      end

      it 'raises error for nil' do
        expect do
          described_class.new(name, nil, error_class:).normalize
        end.to raise_error(ArgumentError, 'lease_duration must be a positive finite number')
      end

      it 'raises error for string' do
        expect do
          described_class.new(name, '42', error_class:).normalize
        end.to raise_error(ArgumentError, 'lease_duration must be a positive finite number')
      end

      it 'raises error for array' do
        expect do
          described_class.new(name, [42], error_class:).normalize
        end.to raise_error(ArgumentError, 'lease_duration must be a positive finite number')
      end

      it 'raises error for hash' do
        expect do
          described_class.new(name, { value: 42 }, error_class:).normalize
        end.to raise_error(ArgumentError, 'lease_duration must be a positive finite number')
      end

      it 'raises error for zero BigDecimal' do
        expect do
          described_class.new(name, BigDecimal('0'), error_class:).normalize
        end.to raise_error(ArgumentError, 'lease_duration must be a positive finite number')
      end

      it 'raises error for negative BigDecimal' do
        expect do
          described_class.new(name, BigDecimal('-1'), error_class:).normalize
        end.to raise_error(ArgumentError, 'lease_duration must be a positive finite number')
      end
    end

    context 'with custom error class' do
      let(:error_class) { StandardError }

      it 'raises the custom error class' do
        expect do
          described_class.new(name, 0, error_class:).normalize
        end.to raise_error(StandardError, 'lease_duration must be a positive finite number')
      end
    end

    context 'with custom name' do
      let(:name) { :poll_interval }

      it 'includes the custom name in error message' do
        expect do
          described_class.new(name, 0, error_class:).normalize
        end.to raise_error(ArgumentError, 'poll_interval must be a positive finite number')
      end
    end
  end
end
